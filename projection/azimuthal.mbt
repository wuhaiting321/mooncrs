// 兰勃特方位等积投影（LAEA, EPSG 9820）。
//
// 等积方位投影：从投影中心出发的方向角保持真实，面积比例保持 1。
// 欧洲官方统计网格 ETRS89-LAEA（EPSG:3035）用它，因此是欧盟空间数据
// 交换的默认投影之一。

///|
/// 正算。
pub fn laea_forward(
  p : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let dlon = normalize_longitude(lon - p.lon0)
  let sin0 = @math.sin(p.lat0)
  let cos0 = @math.cos(p.lat0)
  let sin_lat = @math.sin(lat)
  let cos_lat = @math.cos(lat)
  let denom = 1.0 + sin0 * sin_lat + cos0 * cos_lat * @math.cos(dlon)
  if denom <= 1.0e-12 {
    raise @types.CrsError::Domain("LAEA：对跖点无法投影")
  }
  let k = (2.0 / denom).sqrt()
  let x = p.fe + p.a * k * cos_lat * @math.sin(dlon)
  let y = p.fnorth +
    p.a * k * (cos0 * sin_lat - sin0 * cos_lat * @math.cos(dlon))
  (x, y)
}

///|
/// 反算。
pub fn laea_inverse(
  p : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let dx = x - p.fe
  let dy = y - p.fnorth
  let rho = (dx * dx + dy * dy).sqrt()
  if rho < 1.0e-9 {
    return (p.lon0, p.lat0)
  }
  let ratio = rho / (2.0 * p.a)
  let clamped = if ratio > 1.0 { 1.0 } else { ratio }
  let cc = 2.0 * @math.asin(clamped)
  let sin_c = @math.sin(cc)
  let cos_c = @math.cos(cc)
  let sin0 = @math.sin(p.lat0)
  let cos0 = @math.cos(p.lat0)
  let lat = @math.asin(cos_c * sin0 + (dy * sin_c * cos0) / rho)
  let lon = p.lon0 + @math.atan2(dx * sin_c, rho * cos0 * cos_c - dy * sin0 * sin_c)
  (normalize_longitude(lon), lat)
}
