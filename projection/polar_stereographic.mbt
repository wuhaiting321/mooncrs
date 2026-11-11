// 极射赤面投影（EPSG 9810 variant A / 9829 variant B）。
//
// 极区最常用的投影：从极点向赤道方向做等角投影，经线是直线、纬线是圆。
// 两个变体的区别只在尺度因子的来源：
// - A：直接给 k0（如 UPS 的 0.994）；
// - B：给标准纬线，k0 由该纬线上尺度为真反推。

///|
/// 正算。`lat0` 的符号决定投影到北极还是南极。
pub fn polar_stereo_forward(
  p : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let dlon = normalize_longitude(lon - p.lon0)
  let t = t_func(lat, p.e)
  let rho = 2.0 * p.a * p.k0 * t / q_constant(p.e)
  if p.lat0 >= 0.0 {
    (p.fe + rho * @math.sin(dlon), p.fnorth - rho * @math.cos(dlon))
  } else {
    (p.fe + rho * @math.sin(dlon), p.fnorth + rho * @math.cos(dlon))
  }
}

///|
/// 反算。
pub fn polar_stereo_inverse(
  p : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let dx = x - p.fe
  let dy = y - p.fnorth
  let rho = (dx * dx + dy * dy).sqrt()
  if rho == 0.0 {
    return (p.lon0, if p.lat0 >= 0.0 { pi / 2.0 } else { -pi / 2.0 })
  }
  let t = rho * q_constant(p.e) / (2.0 * p.a * p.k0)
  let lat = geodetic_from_t(t, p.e2)
  let dlon = if p.lat0 >= 0.0 {
    @math.atan2(dx, -dy)
  } else {
    @math.atan2(dx, dy)
  }
  (normalize_longitude(p.lon0 + dlon), lat)
}
