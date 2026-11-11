// 墨卡托族：等角圆柱投影。
//
// 三个变体必须严格区分，混用会造成几十公里级偏差：
// - EPSG:9804（1SP）：给定原点纬度与 k0，椭球公式；
// - EPSG:9805（2SP）：给定标准纬线，k0 由标准纬线导出；
// - EPSG:1024（Pseudo / Web）：**球面**公式套在椭球长半轴上，仅为瓦片对齐。

///|
/// 椭球墨卡托正算（9804 / 9805 共用）。
pub fn mercator_forward(
  p : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let dlon = normalize_longitude(lon - p.lon0)
  let x = p.fe + p.a * p.k0 * dlon
  let t = t_func(lat, p.e)
  let y = p.fnorth - p.a * p.k0 * @math.ln(t)
  (x, y)
}

///|
/// 椭球墨卡托反算。
pub fn mercator_inverse(
  p : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let dlon = (x - p.fe) / (p.a * p.k0)
  let t = @math.exp(-(y - p.fnorth) / (p.a * p.k0))
  (normalize_longitude(p.lon0 + dlon), geodetic_from_t(t, p.e2))
}

///|
/// Web Mercator 正算。
///
/// 刻意使用球面公式（e 视为 0），这是 EPSG:3857 的定义，不是精度缺陷。
pub fn web_mercator_forward(
  p : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let dlon = normalize_longitude(lon)
  let x = p.fe + p.a * dlon
  let y = p.fnorth + p.a * @math.ln(@math.tan(pi / 4.0 + lat / 2.0))
  (x, y)
}

///|
/// Web Mercator 反算。
pub fn web_mercator_inverse(
  p : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let dlon = (x - p.fe) / p.a
  let lat = 2.0 * @math.atan(@math.exp((y - p.fnorth) / p.a)) - pi / 2.0
  (normalize_longitude(dlon), lat)
}
