// 卡西尼-塞尔德纳（Cassini-Soldner, EPSG 9806）。
//
// 历史意义大于现代用途：它是横轴墨卡托的前身，英国印度测量局与中国
// 1954 北京坐标系的部分老图件用它。特征是中央经线是直线、其余经线弯曲，
// 且**不是等角**投影——离开中央经线越远，形状畸变越明显。
//
// 因此本实现刻意只在 |Δλ| ≤ 2° 内提供，超出时由调用方决定是否告警。

///|
/// 正算。
pub fn cassini_forward(
  p : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let dlon = normalize_longitude(lon - p.lon0)
  let s = @math.sin(lat)
  let w = 1.0 - p.e2 * s * s
  let n = p.a / w.sqrt()
  let t = @math.tan(lat)
  let tt = t * t
  let c = p.e2 * @math.cos(lat) * @math.cos(lat) / (1.0 - p.e2)
  let aa = @math.cos(lat) * dlon
  let aa2 = aa * aa
  let m0 = meridian_arc(p.a, p.e2, p.lat0)
  let m = meridian_arc(p.a, p.e2, lat)
  let x = p.fe +
    n * (aa - tt * aa * aa2 / 6.0 - (8.0 - tt + 8.0 * c) * tt * aa * aa2 * aa2 / 120.0)
  let y = p.fnorth + (m - m0) +
    n * t * (aa2 / 2.0 + (5.0 - tt + 6.0 * c) * aa2 * aa2 / 24.0)
  (x, y)
}

///|
/// 反算。
pub fn cassini_inverse(
  p : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let m0 = meridian_arc(p.a, p.e2, p.lat0)
  let m1 = m0 + (y - p.fnorth)
  let lat1 = latitude_from_meridian_arc(p.a, p.e2, m1)
  let s1 = @math.sin(lat1)
  let w = 1.0 - p.e2 * s1 * s1
  let n1 = p.a / w.sqrt()
  let r1 = p.a * (1.0 - p.e2) / (w * w.sqrt())
  let t1 = @math.tan(lat1)
  let tt1 = t1 * t1
  let d = (x - p.fe) / n1
  let d2 = d * d
  let lat = lat1 - (n1 * t1 / r1) * (d2 / 2.0 - (1.0 + 3.0 * tt1) * d2 * d2 / 24.0)
  let dlon = (d - tt1 * d * d2 / 3.0 +
    (1.0 + 3.0 * tt1) * tt1 * d * d2 * d2 / 15.0) / @math.cos(lat1)
  (normalize_longitude(p.lon0 + dlon), lat)
}
