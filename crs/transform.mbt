// 转换管道：任意 CRS ↔ 任意 CRS。
//
// 六步流水线（结构没变，变的是第 4 步"怎么选运算"）：
//   1. 按轴序与单位把入参摊平成 (easting, northing) 或 (lon, lat)
//   2. 反算到本基准的大地坐标（弧度）
//   3. 加上本初子午线偏移，得到相对格林尼治的经度
//   4. 按注册表选一条**带范围与精度**的坐标运算，执行基准变换
//   5. 扣掉目标基准的本初子午线偏移
//   6. 正算到目标 CRS 的坐标，并换算成目标单位
//
// 与 0.1 版的关键差异在第 4 步：
//   · 运算从「基准上写死的一套参数」变成「注册表里按适用范围挑的一条记录」
//   · 挑不到就报错，不再静默按"基准重合"返回原值
//   · 每次转换都能产出一份 TransformationReport，说明用了什么、精度多少、
//     跳过了什么、有什么保留

///|
/// 坐标转换（二维）。高程按 0 处理，适合地图坐标。
///
/// 轴序按各 CRS 自身的定义：WKT2 里写了 `AXIS["Latitude",north]` 的坐标系
/// 就按"纬, 经"解释入参。内置 EPSG 注册表统一标注为 `LonLat`/`EastNorth`，
/// 与 GeoJSON、几乎所有 Web API 的习惯一致。
pub fn transform(
  from : @types.Crs,
  to : @types.Crs,
  x : Double,
  y : Double,
) -> (Double, Double) raise @types.CrsError {
  let r = convert(from, to, x, y, 0.0)
  (r.0, r.1)
}

///|
/// 坐标转换（三维）。地理/投影坐标系的高程单位为米，
/// 地心坐标系的高程即 Z 分量。
pub fn transform_3d(
  from : @types.Crs,
  to : @types.Crs,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) raise @types.CrsError {
  let r = convert(from, to, x, y, z)
  (r.0, r.1, r.2)
}

///|
/// 带报告的转换：坐标 + 用了哪条运算 + 精度 + 警告。
///
/// 需要判断"这个结果能不能用"的场合必须走这个入口，而不是 `transform`。
pub fn transform_report(
  from : @types.Crs,
  to : @types.Crs,
  x : Double,
  y : Double,
) -> (Double, Double, @operation.TransformationReport) raise @types.CrsError {
  let r = convert(from, to, x, y, 0.0)
  (r.0, r.1, r.3)
}

///|
/// 无参数兜底：只搬经纬度，不做基准变换。
///
/// 这是**唯一的降级入口**，名字里带 `ballpark` 是刻意的——用它就必须
/// 知道自己在做什么。它存在的理由：有些数据管道只需要"位置大致对"，
/// 宁可拿到一个带明确警告的粗略结果，也不要程序直接崩。默认入口
/// `transform` 永远不会走到这里。
pub fn transform_ballpark(
  from : @types.Crs,
  to : @types.Crs,
  x : Double,
  y : Double,
) -> (Double, Double, @operation.TransformationReport) raise @types.CrsError {
  let geo = to_geodetic(from, x, y, 0.0)
  let lon_greenwich = geo.0 + from.datum().prime_meridian * deg_to_rad
  let lon_target = lon_greenwich - to.datum().prime_meridian * deg_to_rad
  let result = from_geodetic(to, lon_target, geo.1, geo.2)
  let op = @operation.CoordinateOperation::new(
    code="LOCAL:BALLPARK",
    name="无参数兜底（不做基准变换）",
    method_kind=@operation.Ballpark,
    params=@operation.OperationParams::NoParams,
    source=from.datum().key,
    target=to.datum().key,
    area=@operation.BoundingBox::world(),
    accuracy_m=None,
    authority="definition",
    note="只在两套椭球/投影之间搬运经纬度，源与目标基准的差异被完全忽略",
  )
  let warnings : Array[String] = [
    "已显式降级：未做任何基准变换。" +
    from.datum().key +
    " 与 " +
    to.datum().key +
    " 的差异被忽略，误差可能从米级到百米级",
    "该结果不可用于成果提交、面积量算或任何精度判断，只能用于量级参考",
  ]
  let report = @operation.TransformationReport::new(
    operation=op,
    warnings~,
    steps=[
      "反算到源基准大地坐标",
      "直接更换椭球与投影（跳过基准变换）",
      "正算到目标坐标系",
    ],
    skipped=[],
  )
  (result.0, result.1, report)
}

///|
/// 批量转换。单点转换的开销主要是构造投影器（每次都要算 Krüger 级数、
/// 圆锥常数），批量接口按同一对 CRS 复用一次构造，也复用一次运算选择。
pub fn transform_many(
  from : @types.Crs,
  to : @types.Crs,
  points : Array[(Double, Double)],
) -> Array[(Double, Double)] raise @types.CrsError {
  let out : Array[(Double, Double)] = []
  let src = source_frame(from)
  let rad_to_deg = 1.0 / deg_to_rad
  let dst = target_frame(to)
  let plan = build_plan(from, to)
  let pm_from = from.datum().prime_meridian * deg_to_rad
  let pm_to = to.datum().prime_meridian * deg_to_rad
  for point in points {
    let geo = src.to_geodetic(point.0, point.1, 0.0)
    let lon_greenwich = geo.0 + pm_from
    let op = match pick(plan, lon_greenwich * rad_to_deg, geo.1 * rad_to_deg) {
      Some(op) => op
      None =>
        raise @types.CrsError::UnsupportedOperation(
          @operation.outside_message(
            plan.fallback,
            lon_greenwich * rad_to_deg,
            geo.1 * rad_to_deg,
          ),
        )
    }
    let shifted = apply_operation(
      op,
      from.datum().ellipsoid.semi_major,
      from.datum().ellipsoid.e2(),
      to.datum().ellipsoid.semi_major,
      to.datum().ellipsoid.e2(),
      lon_greenwich,
      geo.1,
      geo.2,
    )
    let result = dst.from_geodetic(shifted.0 - pm_to, shifted.1, shifted.2)
    out.push((result.0, result.1))
  }
  out
}

///|
/// 核心：一次转换的全部上下文。
///
/// 返回 `(x, y, z, report)`。内部只用一次运算选择，保证 2D/3D/报告三个
/// 入口的行为完全一致——否则"带报告的结果"和"普通结果"可能悄悄不同。
fn convert(
  from : @types.Crs,
  to : @types.Crs,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double, @operation.TransformationReport) raise @types.CrsError {
  let geo = to_geodetic(from, x, y, z)
  let pm_from = from.datum().prime_meridian * deg_to_rad
  let pm_to = to.datum().prime_meridian * deg_to_rad
  let lon_greenwich = geo.0 + pm_from
  let plan = build_plan(from, to)
  let rad_to_deg = 1.0 / deg_to_rad
  let op = match pick(plan, lon_greenwich * rad_to_deg, geo.1 * rad_to_deg) {
    Some(op) => op
    None =>
      raise @types.CrsError::UnsupportedOperation(
        @operation.outside_message(
          plan.fallback,
          lon_greenwich * rad_to_deg,
          geo.1 * rad_to_deg,
        ),
      )
  }
  let shifted = apply_operation(
    op,
    from.datum().ellipsoid.semi_major,
    from.datum().ellipsoid.e2(),
    to.datum().ellipsoid.semi_major,
    to.datum().ellipsoid.e2(),
    lon_greenwich,
    geo.1,
    geo.2,
  )
  let result = from_geodetic(to, shifted.0 - pm_to, shifted.1, shifted.2)
  let report = @operation.TransformationReport::new(
    operation=op,
    warnings=plan.warnings,
    steps=steps_of(from, to, op, pm_from, pm_to),
    skipped=plan.skipped,
  )
  (result.0, result.1, result.2, report)
}

///|
/// 一次转换的计划：候选运算（已排序）+ 被跳过的 + 保留意见。
pub struct Plan {
  candidates : Array[@operation.CoordinateOperation]
  skipped : Array[String]
  warnings : Array[String]
  /// 用于"点不在范围内"报错时展示范围的兜底记录。
  fallback : @operation.CoordinateOperation
} 

///|
/// 构造计划。
///
/// 三件事在这里定下来，之后不再随点变化：
///   · 用注册表还是用定义文本自带的 towgs84
///   · 哪些候选因缺数据被排除（记入 skipped，报告里要给用户看）
///   · 有哪些"结果可用性"层面的保留（精度未声明、假定重合等）
fn build_plan(from : @types.Crs, to : @types.Crs) -> Plan raise @types.CrsError {
  let src = from.datum()
  let dst = to.datum()
  let warnings : Array[String] = []
  let skipped : Array[String] = []
  let candidates : Array[@operation.CoordinateOperation] = []

  // 定义文本自带的 towgs84 优先，但它只对"转入 WGS84 族"有意义。
  match from.inline_towgs84() {
    Some(h) => {
      if wgs84_family(dst.key) {
        let op_method = if h.is_translation_only() {
          @operation.GeocentricTranslation3
        } else {
          @operation.PositionVector7
        }
        candidates.push(
          @operation.CoordinateOperation::new(
            code="LOCAL:INLINE_TOWGS84",
            name="定义文本自带的 towgs84",
            method_kind=op_method,
            params=@operation.OperationParams::Helmert(h),
            source=src.key,
            target=dst.key,
            area=@operation.BoundingBox::world(),
            accuracy_m=None,
            authority="definition text",
            note="参数来自 WKT 的 TOWGS84 或 PROJ 的 +towgs84，无适用范围、无精度声明",
          ),
        )
        warnings.push(
          "本次使用定义文本自带的参数（" +
          h.dx.to_string() +
          ", " +
          h.dy.to_string() +
          ", " +
          h.dz.to_string() +
          " 等）：没有适用范围与标称精度，转换结果不可用于成果提交",
        )
      } else {
        warnings.push(
          "定义文本自带了 towgs84，但它只描述转入 WGS84 的方向；本次目标是 " +
          dst.key +
          "，已改用注册表运算",
        )
      }
    }
    None => ()
  }

  let registered = @operation.resolve(src, dst)
  for op in registered {
    if op.needs_grid() {
      skipped.push(
        op.code +
        "（" +
        op.accuracy_text() +
        "）更精确，但需要网格数据 " +
        grid_id_of(op) +
        "；当前未提供，已跳过",
      )
    } else {
      candidates.push(op)
    }
  }

  if candidates.length() == 0 {
    if skipped.length() > 0 {
      raise @types.CrsError::UnsupportedOperation(
        "只找到网格类运算，但网格数据不可用：" + skipped[0],
      )
    }
    raise @types.CrsError::UnsupportedOperation(
      @operation.missing_message(src, dst),
    )
  }

  // 兜底记录：用于范围报错时展示"本来该用哪条、范围在哪"。
  let fallback = candidates[0]
  for op in candidates {
    match op.accuracy_m {
      Some(_) => ()
      None =>
        warnings.push(
          "运算 " + op.code + " 未声明精度，结果只能作参考，不能作为精度依据",
        )
    }
    if op.is_assumed() {
      warnings.push("两侧基准至少有一方未在定义中声明，仅因椭球一致而假定重合；误差未知")
    }
  }

  { candidates, skipped, warnings, fallback }
}

///|
/// 在候选里挑第一条"适用于该点"的运算。
fn pick(
  plan : Plan,
  lon : Double,
  lat : Double,
) -> @operation.CoordinateOperation? {
  for op in plan.candidates {
    if op.area.contains(lon, lat) {
      return Some(op)
    }
  }
  None
}

///|
/// 转换步骤的文本描述。给报告用，顺序即执行顺序。
fn steps_of(
  from : @types.Crs,
  to : @types.Crs,
  op : @operation.CoordinateOperation,
  pm_from : Double,
  pm_to : Double,
) -> Array[String] {
  let steps : Array[String] = []
  steps.push("入参换轴换单位 → " + from.name() + " 上的大地坐标")
  if pm_from != 0.0 {
    steps.push("加源本初子午线偏移 " + from.datum().prime_meridian.to_string() + "°")
  }
  steps.push("坐标运算 " + op.code + "（" + op.method_kind.label() + "）")
  if pm_to != 0.0 {
    steps.push("扣目标本初子午线偏移 " + to.datum().prime_meridian.to_string() + "°")
  }
  steps.push("正算到 " + to.name() + " 并换算单位")
  steps
}

///|
/// 目标基准是否属于"与 WGS84 厘米级一致"的家族。
fn wgs84_family(key : String) -> Bool {
  key == "WGS84" ||
  key == "ETRS89" ||
  key == "CGCS2000" ||
  key == "RGF93" ||
  key == "GDA94"
}

///|
/// 取运算绑定的网格标识。
fn grid_id_of(op : @operation.CoordinateOperation) -> String {
  match op.params {
    Grid(id) => id
    _ => "（未指定）"
  }
}

///|
/// 把入参换算成"本基准上的大地坐标"（弧度 + 米）。
///
/// 投影坐标系的轴序（`NorthEast`）在这里处理：先换轴，再按线性单位
/// 换算成米，最后反算。顺序错了会把 500000 当作纬度送进反算器，
/// 得到的是 `Domain` 错误而不是错值——算是运气好的情况。
pub fn to_geodetic(
  crs : @types.Crs,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) raise @types.CrsError {
  match crs {
    Geographic(g) => {
      let pair = match g.axis {
        LatLon => (y, x)
        _ => (x, y)
      }
      (g.unit.to_radians(pair.0), g.unit.to_radians(pair.1), z)
    }
    Projected(p) => {
      let pair = match p.axis {
        NorthEast => (y, x)
        _ => (x, y)
      }
      let proj = projection_of(p)
      let easting = p.unit.to_metres(pair.0)
      let northing = p.unit.to_metres(pair.1)
      let geo = proj.inverse(easting, northing)
      (geo.0, geo.1, z)
    }
    Geocentric(c) => {
      let xm = c.unit.to_metres(x)
      let ym = c.unit.to_metres(y)
      let zm = c.unit.to_metres(z)
      geocentric_to_geodetic(c.datum.ellipsoid.semi_major, c.datum.ellipsoid.e2(), xm, ym, zm)
    }
  }
}

///|
/// 把大地坐标（弧度 + 米）还原成目标 CRS 的坐标。
pub fn from_geodetic(
  crs : @types.Crs,
  lon : Double,
  lat : Double,
  h : Double,
) -> (Double, Double, Double) raise @types.CrsError {
  match crs {
    Geographic(g) => {
      let lon_v = g.unit.from_radians(lon)
      let lat_v = g.unit.from_radians(lat)
      match g.axis {
        LatLon => (lat_v, lon_v, h)
        _ => (lon_v, lat_v, h)
      }
    }
    Projected(p) => {
      let proj = projection_of(p)
      let xy = proj.forward(lon, lat)
      let easting = p.unit.from_metres(xy.0)
      let northing = p.unit.from_metres(xy.1)
      match p.axis {
        NorthEast => (northing, easting, h)
        _ => (easting, northing, h)
      }
    }
    Geocentric(c) => {
      let xyz = geodetic_to_geocentric(
        c.datum.ellipsoid.semi_major,
        c.datum.ellipsoid.e2(),
        lon,
        lat,
        h,
      )
      (
        c.unit.from_metres(xyz.0),
        c.unit.from_metres(xyz.1),
        c.unit.from_metres(xyz.2),
      )
    }
  }
}

///|
/// 预构造的坐标系"帧"，批量转换用。
///
/// 把投影器缓存在这里，避免每点重建一次 Krüger 级数（那是 60 多次
/// 三角函数，占单点总耗时的一半以上）。
pub struct Frame {
  crs : @types.Crs
  projection : @projection.Projection?
} 

///|
/// 由 CRS 构造帧。
pub fn source_frame(crs : @types.Crs) -> Frame raise @types.CrsError {
  target_frame(crs)
}

///|
/// 由 CRS 构造帧（与 `source_frame` 同义，分开命名只为可读性）。
pub fn target_frame(crs : @types.Crs) -> Frame raise @types.CrsError {
  let projection = match crs {
    Projected(p) => Some(projection_of(p))
    _ => None
  }
  { crs, projection }
}

///|
/// 帧上的反算：坐标 → 大地坐标。
pub fn Frame::to_geodetic(
  self : Frame,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) raise @types.CrsError {
  match self.projection {
    Some(proj) =>
      match self.crs {
        Projected(p) => {
          let pair = match p.axis {
            NorthEast => (y, x)
            _ => (x, y)
          }
          let geo = proj.inverse(p.unit.to_metres(pair.0), p.unit.to_metres(pair.1))
          (geo.0, geo.1, z)
        }
        _ => to_geodetic(self.crs, x, y, z)
      }
    None => to_geodetic(self.crs, x, y, z)
  }
}

///|
/// 帧上的正算：大地坐标 → 坐标。
pub fn Frame::from_geodetic(
  self : Frame,
  lon : Double,
  lat : Double,
  h : Double,
) -> (Double, Double, Double) raise @types.CrsError {
  match self.projection {
    Some(proj) =>
      match self.crs {
        Projected(p) => {
          let xy = proj.forward(lon, lat)
          let easting = p.unit.from_metres(xy.0)
          let northing = p.unit.from_metres(xy.1)
          match p.axis {
            NorthEast => (northing, easting, h)
            _ => (easting, northing, h)
          }
        }
        _ => from_geodetic(self.crs, lon, lat, h)
      }
    None => from_geodetic(self.crs, lon, lat, h)
  }
}
