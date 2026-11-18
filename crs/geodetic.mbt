// 大地坐标 ↔ 地心直角坐标，以及 Helmert 七参数。
//
// 为什么所有基准转换都绕道地心：不同椭球上的"同一个经纬度"根本不是
// 同一个物理点。要跨基准，必须先把点放到一个与椭球无关的参考系里
// （地心 XYZ），在那里做平移旋转缩放，再落到目标椭球上。少了这一步，
// 直接对经纬度加减 delta，误差可以达到几百米。

///|
/// π。
let pi : Double = 3.141592653589793

///|
/// 角秒 → 弧度。Helmert 的旋转量以角秒给出。
let arcsec_to_rad : Double = 3.141592653589793 / 648000.0

///|
/// 大地坐标 → 地心直角坐标（EPSG 9602 的正向）。
///
/// `lon`/`lat` 为弧度，`h` 为大地高（米）。
pub fn geodetic_to_geocentric(
  a : Double,
  e2 : Double,
  lon : Double,
  lat : Double,
  h : Double,
) -> (Double, Double, Double) {
  let sin_lat = @math.sin(lat)
  let cos_lat = @math.cos(lat)
  let sin_lon = @math.sin(lon)
  let cos_lon = @math.cos(lon)
  let w = 1.0 - e2 * sin_lat * sin_lat
  let n = a / w.sqrt()
  let x = (n + h) * cos_lat * cos_lon
  let y = (n + h) * cos_lat * sin_lon
  let z = (n * (1.0 - e2) + h) * sin_lat
  (x, y, z)
}

///|
/// 地心直角坐标 → 大地坐标（EPSG 9602 的反向）。
///
/// 用不动点迭代而不是 Bowring 闭式解：迭代在极区附近不会退化，
/// 且实现只有五行，出错概率比闭式解低。收敛判据取 1e-12 弧度
/// （约 6 微米），远超实际精度需求。
pub fn geocentric_to_geodetic(
  a : Double,
  e2 : Double,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  let p = (x * x + y * y).sqrt()
  let lon = if p < 1.0e-12 { 0.0 } else { @math.atan2(y, x) }
  if p < 1.0e-9 {
    // 极点：经度无定义，高度退化为 |z| - b。
    let b = a * (1.0 - e2).sqrt()
    return (lon, if z >= 0.0 { pi / 2.0 } else { -pi / 2.0 }, z.abs() - b)
  }
  let mut lat = @math.atan2(z, p * (1.0 - e2))
  let mut h = 0.0
  let mut i = 0
  while i < 12 {
    let sin_lat = @math.sin(lat)
    let n = a / (1.0 - e2 * sin_lat * sin_lat).sqrt()
    h = p / @math.cos(lat) - n
    let next = @math.atan2(z, p * (1.0 - e2 * n / (n + h)))
    let delta = (next - lat).abs()
    lat = next
    if delta < 1.0e-12 {
      break
    }
    i = i + 1
  }
  (lon, lat, h)
}

///|
/// Helmert 七参数正向（源基准 → 目标基准）。
///
/// 旋转矩阵按 EPSG 9606（Position Vector）写：
/// ```
/// |  1  -rz   ry |
/// | rz    1  -rx |
/// |-ry   rx    1 |
/// ```
/// EPSG 9607（Coordinate Frame）的旋转方向相反，通过把角度取负实现，
/// 而不是复制一份矩阵——两套矩阵并存是这类代码最常见的错误来源。
pub fn helmert_forward(
  h : @types.Helmert,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  let sign = match h.convention {
    @types.PositionVector => 1.0
    @types.CoordinateFrame => -1.0
  }
  let rx = h.rx * arcsec_to_rad * sign
  let ry = h.ry * arcsec_to_rad * sign
  let rz = h.rz * arcsec_to_rad * sign
  let s = 1.0 + h.ds * 1.0e-6
  let xr = (x - rz * y + ry * z) * s
  let yr = (rz * x + y - rx * z) * s
  let zr = (-ry * x + rx * y + z) * s
  (h.dx + xr, h.dy + yr, h.dz + zr)
}

///|
/// Helmert 七参数反向（目标基准 → 源基准）。
///
/// 严格做法是求逆矩阵，但旋转角最大不过几十角秒（1e-4 弧度量级），
/// 正交矩阵与其转置的差异在 1e-9 以下，工程上直接取转置（角度取负）
/// 再扣掉平移与尺度，误差远小于控制点本身的精度。
pub fn helmert_inverse(
  h : @types.Helmert,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  let sign = match h.convention {
    @types.PositionVector => -1.0
    @types.CoordinateFrame => 1.0
  }
  let rx = h.rx * arcsec_to_rad * sign
  let ry = h.ry * arcsec_to_rad * sign
  let rz = h.rz * arcsec_to_rad * sign
  let s = 1.0 + h.ds * 1.0e-6
  let x0 = (x - h.dx) / s
  let y0 = (y - h.dy) / s
  let z0 = (z - h.dz) / s
  let xr = x0 - rz * y0 + ry * z0
  let yr = rz * x0 + y0 - rx * z0
  let zr = -ry * x0 + rx * y0 + z0
  (xr, yr, zr)
}

///|
/// 按一条坐标运算把大地坐标从源椭球搬到目标椭球。
///
/// 运算本身是数据（带来源、范围、精度），这里是它唯一的执行点。
/// 每个方法分支都必须对"参数形态不对"和"缺数据"给出可操作的错误，
/// 不许回退成"什么都不做"——0.1 版正是在这里静默返回原值，被打了回来。
pub fn apply_operation(
  op : @operation.CoordinateOperation,
  a_from : Double,
  e2_from : Double,
  a_to : Double,
  e2_to : Double,
  lon : Double,
  lat : Double,
  h : Double,
  grids : @grid.GridSet,
) -> (Double, Double, Double) raise @types.CrsError {
  match op.method_kind {
    Identity | Assumed | Ballpark => (lon, lat, h)
    GeocentricTranslation3 | PositionVector7 | CoordinateFrame7 | Molodensky => {
      let helmert = match op.params {
        Helmert(hm) => hm
        _ =>
          raise @types.CrsError::Invalid(
            "运算 " + op.code + " 声明为 Helmert 类方法，但没有 Helmert 参数",
          )
      }
      let geo = geodetic_to_geocentric(a_from, e2_from, lon, lat, h)
      let shifted = if op.reversed {
        helmert_inverse(helmert, geo.0, geo.1, geo.2)
      } else {
        helmert_forward(helmert, geo.0, geo.1, geo.2)
      }
      geocentric_to_geodetic(a_to, e2_to, shifted.0, shifted.1, shifted.2)
    }
    Ntv2Grid => {
      let grid_id = match op.params {
        Grid(id) => id
        _ => op.code
      }
      let g = match grids.get(grid_id) {
        Some(g) => g
        None =>
          raise @types.CrsError::UnsupportedOperation(
            "运算 " +
            op.code +
            " 需要网格文件 " +
            grid_id +
            ".gsb，当前未提供（已登记的网格：" +
            grids_text(grids) +
            "）。网格数据不随本库分发，获取方式见 docs/DATA.md",
          )
      }
      // 网格改正工作在"度"上，而管道内部一律用弧度。
      let lon_deg = lon / deg_to_rad
      let lat_deg = lat / deg_to_rad
      match g.apply(lon_deg, lat_deg, reversed=op.reversed) {
        Some(s) =>
          ((lon_deg + s.dlon) * deg_to_rad, (lat_deg + s.dlat) * deg_to_rad, h)
        None =>
          raise @types.CrsError::UnsupportedOperation(
            g.outside_message(lon_deg, lat_deg) + "。见 docs/DATA.md 的数据覆盖说明",
          )
      }
    }
    NadconGrid => {
      let grid_id = match op.params {
        Grid(id) => id
        _ => op.code
      }
      raise @types.CrsError::UnsupportedOperation(
        "运算 " +
        op.code +
        " 使用 NADCON 格式（.las / .los），本版只实现了 NTv2（.gsb）解析。" +
        "请改用海外的等价 NTv2 版本，或等待 NADCON 支持；说明见 docs/DATA.md（网格标识 " +
        grid_id +
        "）",
      )
    }
  }
}

///|
/// 已加载网格的标识拼成一行，用于报错时说明"你到底加载了什么"。
fn grids_text(grids : @grid.GridSet) -> String {
  let ids = grids.ids()
  if ids.length() == 0 {
    return "无"
  }
  let sb = StringBuilder()
  let mut i = 0
  while i < ids.length() {
    if i > 0 {
      sb.write_string(" / ")
    }
    sb.write_string(ids[i])
    i = i + 1
  }
  sb.to_string()
}
