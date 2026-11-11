// 横轴墨卡托（Transverse Mercator，EPSG 9807）与 UTM。
//
// 算法选择：Krüger n 级数（Karney 2011, "Transverse Mercator with an
// accuracy of a few nanometers"），而非 Snyder 的 A³/A⁵ 幂级数。
//
// 为什么不直接用 Snyder 式 8-9~8-17：那组公式在离开中央子午线 3° 处误差
// 已达厘米级，9° 处超过米级。UTM 分带边缘正好是 3°，中国的 3 度带高斯
// 投影也贴着这个边界，厘米级误差不可接受。Krüger 六阶级数在同一范围内
// 误差在纳米量级，且对所有纬度稳定。

///|
/// Krüger 级数的系数集。
///
/// 只与第三扁率 n 有关，构造投影时算一次即可。批量转换上万点时，
/// 这组系数如果每次重算会带来可观的浪费。
pub struct KrugerSeries {
  n : Double
  /// 母线尺度因子 A = a/(1+n)(1 + n²/4 + n⁴/64 + n⁶/256)。
  big_a : Double
  /// 正算系数 α1..α6。
  alpha : Array[Double]
  /// 反算系数 β1..β6。
  beta : Array[Double]
  /// 等角纬度反解系数 δ1..δ6。
  delta : Array[Double]
} derive(Debug)

///|
pub extend KrugerSeries with @debug.Debug::{to_repr}

///|
/// 空系数集，供非横轴墨卡托的投影占位使用。
pub fn KrugerSeries::zero() -> KrugerSeries {
  {
    n: 0.0,
    big_a: 0.0,
    alpha: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    beta: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    delta: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  }
}

///|
/// 由椭球构造 Krüger 系数集。
pub fn KrugerSeries::new(ellipsoid : @types.Ellipsoid) -> KrugerSeries {
  let a = ellipsoid.semi_major
  let n = ellipsoid.third_flattening()
  let n2 = n * n
  let n3 = n2 * n
  let n4 = n3 * n
  let n5 = n4 * n
  let n6 = n5 * n
  let alpha = [
    n / 2.0 - 2.0 * n2 / 3.0 + 5.0 * n3 / 16.0 + 41.0 * n4 / 180.0 -
    127.0 * n5 / 288.0 + 7891.0 * n6 / 37800.0,
    13.0 * n2 / 48.0 - 3.0 * n3 / 5.0 + 557.0 * n4 / 1440.0 + 281.0 * n5 / 630.0 -
    1983433.0 * n6 / 1935360.0,
    61.0 * n3 / 240.0 - 103.0 * n4 / 140.0 + 15061.0 * n5 / 26880.0 +
    167603.0 * n6 / 181440.0,
    49561.0 * n4 / 161280.0 - 179.0 * n5 / 168.0 + 6601661.0 * n6 / 7257600.0,
    34729.0 * n5 / 80640.0 - 3418889.0 * n6 / 1995840.0,
    212378941.0 * n6 / 319334400.0,
  ]
  let beta = [
    n / 2.0 - 2.0 * n2 / 3.0 + 37.0 * n3 / 96.0 - n4 / 360.0 - 81.0 * n5 / 512.0 +
    96199.0 * n6 / 604800.0,
    n2 / 48.0 + n3 / 15.0 - 437.0 * n4 / 1440.0 + 46.0 * n5 / 105.0 -
    1118711.0 * n6 / 3870720.0,
    17.0 * n3 / 480.0 - 37.0 * n4 / 840.0 - 209.0 * n5 / 4480.0 + 5569.0 * n6 / 90720.0,
    4397.0 * n4 / 161280.0 - 11.0 * n5 / 504.0 - 830251.0 * n6 / 7257600.0,
    4583.0 * n5 / 161280.0 - 108847.0 * n6 / 3991680.0,
    20648693.0 * n6 / 638668800.0,
  ]
  let delta = [
    2.0 * n - 2.0 * n2 / 3.0 - 2.0 * n3 + 116.0 * n4 / 45.0 + 26.0 * n5 / 45.0 -
    2854.0 * n6 / 675.0,
    7.0 * n2 / 3.0 - 8.0 * n3 / 5.0 - 227.0 * n4 / 45.0 + 2704.0 * n5 / 315.0 +
    2323.0 * n6 / 945.0,
    56.0 * n3 / 15.0 - 136.0 * n4 / 35.0 - 1262.0 * n5 / 105.0 + 73814.0 * n6 / 2835.0,
    4279.0 * n4 / 630.0 - 332.0 * n5 / 35.0 - 399572.0 * n6 / 14175.0,
    4174.0 * n5 / 315.0 - 144838.0 * n6 / 6237.0,
    601676.0 * n6 / 22275.0,
  ]
  let big_a = a / (1.0 + n) * (1.0 + n2 / 4.0 + n4 / 64.0 + n6 / 256.0)
  { n, big_a, alpha, beta, delta }
}

///|
/// 原点（中央经线与 lat0 交点）的北坐标。
///
/// Krüger 级数里的 ξ 是从**赤道**起算的，而投影坐标的北向原点由 lat0 决定。
/// 若不减去这个量，任何 lat0 ≠ 0 的投影都会整体偏移一个子午线弧长
/// （英国 BNG 会偏 5,427 km）。这是实现横轴墨卡托最容易漏的一步。
pub fn krueger_origin_northing(
  series : KrugerSeries,
  e : Double,
  k0 : Double,
  lat0 : Double,
) -> Double {
  if lat0 == 0.0 {
    return 0.0
  }
  let s = @math.sin(lat0)
  let t = @math.sinh(@math.asinh(@math.tan(lat0)) - e * @math.atanh(e * s))
  let xi_prime = @math.atan(t)
  let mut xi = xi_prime
  for j in 1..=6 {
    let two_j = 2.0 * j.to_double()
    xi = xi + series.alpha[j - 1] * @math.sin(two_j * xi_prime)
  }
  k0 * series.big_a * xi
}

///|
/// 横轴墨卡托正算：大地坐标（弧度）→ 平面坐标（米）。
///
/// 步骤：
/// 1. 由大地纬度算等角纬度（用 sinh/atanh 形式，靠近极点也不失稳）；
/// 2. 映射到"高斯球"上的 (ξ', η')；
/// 3. 加 Krüger 级数修正得到真 (ξ, η)；
/// 4. 乘尺度因子 A·k0 得到东/北坐标。
pub fn transverse_mercator_forward(
  series : KrugerSeries,
  e : Double,
  lon0 : Double,
  k0 : Double,
  fe : Double,
  fnorth : Double,
  northing_origin : Double,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let dlon = normalize_longitude(lon - lon0)
  let sin_lat = @math.sin(lat)
  let t = @math.sinh(@math.asinh(@math.tan(lat)) - e * @math.atanh(e * sin_lat))
  let cos_dlon = @math.cos(dlon)
  let xi_prime = @math.atan2(t, cos_dlon)
  let eta_prime = @math.atanh(@math.sin(dlon) / (1.0 + t * t).sqrt())
  let mut xi = xi_prime
  let mut eta = eta_prime
  for j in 1..=6 {
    let two_j = 2.0 * j.to_double()
    xi = xi +
      series.alpha[j - 1] * @math.sin(two_j * xi_prime) * @math.cosh(two_j * eta_prime)
    eta = eta +
      series.alpha[j - 1] * @math.cos(two_j * xi_prime) * @math.sinh(two_j * eta_prime)
  }
  let scale = k0 * series.big_a
  (fe + scale * eta, fnorth + scale * xi - northing_origin)
}

///|
/// 横轴墨卡托反算：平面坐标（米）→ 大地坐标（弧度）。
pub fn transverse_mercator_inverse(
  series : KrugerSeries,
  _e2 : Double,
  lon0 : Double,
  k0 : Double,
  fe : Double,
  fnorth : Double,
  northing_origin : Double,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let scale = k0 * series.big_a
  let xi = (y - fnorth + northing_origin) / scale
  let eta = (x - fe) / scale
  let mut xi_prime = xi
  let mut eta_prime = eta
  for j in 1..=6 {
    let two_j = 2.0 * j.to_double()
    xi_prime = xi_prime - series.beta[j - 1] * @math.sin(two_j * xi) * @math.cosh(two_j * eta)
    eta_prime = eta_prime -
      series.beta[j - 1] * @math.cos(two_j * xi) * @math.sinh(two_j * eta)
  }
  let sinh_eta = @math.sinh(eta_prime)
  let chi = @math.asin(@math.sin(xi_prime) / @math.cosh(eta_prime))
  let mut lat = chi
  for j in 1..=6 {
    let two_j = 2.0 * j.to_double()
    lat = lat + series.delta[j - 1] * @math.sin(two_j * chi)
  }
  let dlon = @math.atan2(sinh_eta, @math.cos(xi_prime))
  (normalize_longitude(lon0 + dlon), lat)
}
