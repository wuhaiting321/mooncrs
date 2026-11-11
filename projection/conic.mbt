// 圆锥投影：兰勃特等角圆锥（LCC）与阿尔伯斯等积圆锥。
//
// 两者的正算结构相同（极坐标 → 平面），差别只在半径 ρ 的算法：
// - LCC 用等角纬度 t 的幂，保持角度不变（等角）；
// - Albers 用等积纬度 q，保持面积不变（等积）。
// 反算时 LCC 可直接由 t 反解，Albers 需要牛顿迭代反解 q → φ。

///|
/// LCC 正算（1SP 与 2SP 共用；差异已折算进 conic_factor）。
pub fn lcc_forward(
  p : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let dlon = normalize_longitude(lon - p.lon0)
  let t = t_func(lat, p.e)
  let rho = p.a * p.conic_factor * @math.pow(t, p.conic_n)
  let theta = p.conic_n * dlon
  (p.fe + rho * @math.sin(theta), p.fnorth + p.conic_rho0 - rho * @math.cos(theta))
}

///|
/// LCC 反算。
pub fn lcc_inverse(
  p : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let dx = x - p.fe
  let dy = p.conic_rho0 - (y - p.fnorth)
  let rho = if p.conic_n < 0.0 {
    -((dx * dx + dy * dy).sqrt())
  } else {
    (dx * dx + dy * dy).sqrt()
  }
  let theta = @math.atan2(dx, dy)
  let t = @math.pow(rho / (p.a * p.conic_factor), 1.0 / p.conic_n)
  let lat = geodetic_from_t(t, p.e2)
  (normalize_longitude(p.lon0 + theta / p.conic_n), lat)
}

///|
/// Albers 正算。
pub fn albers_forward(
  p : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let dlon = normalize_longitude(lon - p.lon0)
  let q = authalic_q(lat, p.e2, p.e)
  let rho = p.a * (p.conic_factor - p.conic_n * q).sqrt() / p.conic_n
  let theta = p.conic_n * dlon
  (p.fe + rho * @math.sin(theta), p.fnorth + p.conic_rho0 - rho * @math.cos(theta))
}

///|
/// Albers 反算。
pub fn albers_inverse(
  p : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let dx = x - p.fe
  let dy = p.conic_rho0 - (y - p.fnorth)
  let rho = if p.conic_n < 0.0 {
    -((dx * dx + dy * dy).sqrt())
  } else {
    (dx * dx + dy * dy).sqrt()
  }
  let theta = @math.atan2(dx, dy)
  let scaled = rho * p.conic_n / p.a
  let q = (p.conic_factor - scaled * scaled) / p.conic_n
  let lat = latitude_from_authalic_q(q, p.e2, p.e)
  (normalize_longitude(p.lon0 + theta / p.conic_n), lat)
}

///|
/// 由等积纬度量 q 反解大地纬度。
///
/// 用牛顿迭代而不是 Snyder 的幂级数，原因是级数在 |φ|>70° 时收敛变慢，
/// 而 q → φ 的导数有闭式表达，牛顿法三次内即达 1e-14。
pub fn latitude_from_authalic_q(q : Double, e2 : Double, e : Double) -> Double {
  if e < 1.0e-12 {
    let half = q / 2.0
    return @math.asin(if half > 1.0 { 1.0 } else if half < -1.0 { -1.0 } else { half })
  }
  let half = q / 2.0
  let mut lat = @math.asin(
    if half > 0.9 { 0.9 } else if half < -0.9 { -0.9 } else { half },
  )
  for _ in 0..<12 {
    let s = @math.sin(lat)
    let w = 1.0 - e2 * s * s
    let diff = authalic_q(lat, e2, e) - q
    let deriv = 2.0 * (1.0 - e2) * @math.cos(lat) / (w * w)
    if deriv.abs() < 1.0e-15 {
      break
    }
    lat = lat - diff / deriv
  }
  lat
}
