// 转换管道：任意 CRS ↔ 任意 CRS。
//
// 统一走「六步流水线」：
//   1. 按轴序与单位把入参摊平成 (easting, northing) 或 (lon, lat)
//   2. 反算到本基准的大地坐标（弧度）
//   3. 加上本初子午线偏移，得到相对格林尼治的经度
//   4. 跨基准做地心 Helmert 变换
//   5. 扣掉目标基准的本初子午线偏移
//   6. 正算到目标 CRS 的坐标，并换算成目标单位
//
// 每一步都只依赖上一步的"标准中间量"，所以加新投影方法不需要动管道，
// 加新基准也不需要动投影——这是本项目能保持可维护性的关键结构。

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
  let r = transform_3d(from, to, x, y, 0.0)
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
  let source = to_geodetic(from, x, y, z)
  let lon_greenwich = source.0 + from.datum().prime_meridian * deg_to_rad
  let shifted = shift_datum(from.datum(), to.datum(), lon_greenwich, source.1, source.2)
  let lon_target = shifted.0 - to.datum().prime_meridian * deg_to_rad
  from_geodetic(to, lon_target, shifted.1, shifted.2)
}

///|
/// 批量转换。单点转换的开销主要在构造投影器（每次都要算 Krüger 级数、
/// 圆锥常数），批量接口按同一对 CRS 复用一次构造，适合上万点的场景。
pub fn transform_many(
  from : @types.Crs,
  to : @types.Crs,
  points : Array[(Double, Double)],
) -> Array[(Double, Double)] raise @types.CrsError {
  let out : Array[(Double, Double)] = []
  let src = source_frame(from)
  let dst = target_frame(to)
  for point in points {
    let geo = src.to_geodetic(point.0, point.1, 0.0)
    let lon_greenwich = geo.0 + from.datum().prime_meridian * deg_to_rad
    let shifted = shift_datum(from.datum(), to.datum(), lon_greenwich, geo.1, geo.2)
    let lon_target = shifted.0 - to.datum().prime_meridian * deg_to_rad
    let result = dst.from_geodetic(lon_target, shifted.1, shifted.2)
    out.push((result.0, result.1))
  }
  out
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
