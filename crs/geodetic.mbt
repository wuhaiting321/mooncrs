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
/// 两个基准之间的大地坐标转换（含椭球变化）。
///
/// 流程固定为「源椭球 → 地心 → WGS84 → 目标基准 → 目标椭球」。
/// 始终经过 WGS84 而不是直接两两转换，是因为七参数的定义就是
/// "相对 WGS84"；两两直转会需要 N×(N-1) 套参数，且没有公开来源。
///
/// **没有七参数时不做椭球往返**：把 WGS84 上的经纬度直接搬到 Clarke 1866
/// 上再反算，会让纬度漂移上百米——那不是"转换"，是"强行解释"。
/// 正确的退化行为是保持经纬度不变（只换标注的椭球），这也是 PROJ 在
/// 缺少 `+towgs84` 时的"ballpark"做法。代价是真实误差可能达到百米级，
/// 因此调用方若关心精度，必须显式提供七参数。
pub fn shift_datum(
  from : @types.Datum,
  to : @types.Datum,
  lon : Double,
  lat : Double,
  h : Double,
) -> (Double, Double, Double) {
  let same_ellipsoid = from.ellipsoid.semi_major == to.ellipsoid.semi_major &&
    from.ellipsoid.inverse_flattening == to.ellipsoid.inverse_flattening
  if same_ellipsoid && !from.has_shift() && !to.has_shift() {
    return (lon, lat, h)
  }
  if !from.has_shift() && !to.has_shift() {
    // 两个基准都没有可用的七参数：按"基准重合"处理。
    return (lon, lat, h)
  }
  let a_from = from.ellipsoid.semi_major
  let e2_from = from.ellipsoid.e2()
  let a_to = to.ellipsoid.semi_major
  let e2_to = to.ellipsoid.e2()
  let geo = geodetic_to_geocentric(a_from, e2_from, lon, lat, h)
  let at_wgs = match from.to_wgs84 {
    Some(helmert) => helmert_forward(helmert, geo.0, geo.1, geo.2)
    None => geo
  }
  let at_target = match to.to_wgs84 {
    Some(helmert) => helmert_inverse(helmert, at_wgs.0, at_wgs.1, at_wgs.2)
    None => at_wgs
  }
  geocentric_to_geodetic(a_to, e2_to, at_target.0, at_target.1, at_target.2)
}
