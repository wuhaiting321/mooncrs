// 斜轴墨卡托（Hotine Oblique Mercator, variant B, EPSG 9815）。
//
// 这是全部实现里公式链最长的一个：投影面是一个倾斜的圆柱，切点由
// "投影中心 + 初始线方位角"共同确定。EPSG 把它拆成两次旋转，中间需要
// 七个常量，且**必须减去投影中心的 u 偏移**——漏掉这一步会让坐标整体
// 偏出数百公里（本实现最初就踩了这个坑，见 u_c 的注释）。

///|
/// 斜轴墨卡托的预计算常量。
pub struct HotineCache {
  /// B = sqrt(1 + e²cos⁴φ0/(1-e²))，圆锥常数。
  b_const : Double
  /// A = a·B·k0·sqrt(1-e²)/(1 - e²sin²φ0)，尺度。
  a_const : Double
  /// D = B·sqrt(1-e²)/(cosφ0·sqrt(1-e²sin²φ0))。
  d_const : Double
  /// F = D ± sqrt(D²-1)（φ0 ≥ 0 取加号）。
  f_const : Double
  /// H = F·t0^B。
  h_const : Double
  /// G = (F - 1/F)/2。
  g_const : Double
  /// γ0 = asin(sin αc / D)。
  gamma0 : Double
  /// λ0' = λc - asin(G·tanγ0)/B，转换后的中央经线。
  lon0_prime : Double
  /// 投影中心在 (u, v) 坐标系中的位置。
  ///
  /// **为什么需要它**：上述公式给出的 u 以「自然原点」（初始线与椭球相切
  /// 的点）为零点，而不是投影中心；两者在经度上可差数度，导致 u_c 高达
  /// 数百公里。variant B 的定义是「投影中心对应假东/假北」，因此必须减去
  /// (u_c, v_c)。马来西亚 RSO 场景下漏减会偏出约 660 km。
  u_c : Double
  /// 投影中心的 v 坐标（解析上恒为 0，仍显式计算以便自检）。
  v_c : Double
} derive(Debug)

///|
pub extend HotineCache with @debug.Debug::{to_repr}

///|
/// 空缓存，供非斜轴投影占位。
pub fn HotineCache::zero() -> HotineCache {
  {
    b_const: 0.0,
    a_const: 0.0,
    d_const: 0.0,
    f_const: 0.0,
    h_const: 0.0,
    g_const: 0.0,
    gamma0: 0.0,
    lon0_prime: 0.0,
    u_c: 0.0,
    v_c: 0.0,
  }
}

///|
/// 由缓存常量与点坐标计算中间量 (u, v)，单位米。
///
/// `u` 沿初始线方向、`v` 与之垂直，零点在自然原点。正算与反算共用此
/// 函数，保证两条路径的中间量定义完全一致。
fn hotine_uv(
  c : HotineCache,
  e : Double,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  let dlon = normalize_longitude(lon - c.lon0_prime)
  let t = t_func(lat, e)
  let q = c.h_const / @math.pow(t, c.b_const)
  let s = (q - 1.0 / q) / 2.0
  let tt = (q + 1.0 / q) / 2.0
  let v = @math.sin(c.b_const * dlon)
  let uu = (-v * @math.cos(c.gamma0) + s * @math.sin(c.gamma0)) / tt
  if uu <= -1.0 || uu >= 1.0 {
    raise @types.CrsError::Domain("斜轴墨卡托：点落在投影有效范围外")
  }
  let vv = c.a_const * @math.ln((1.0 - uu) / (1.0 + uu)) / (2.0 * c.b_const)
  let u_final = c.a_const * @math.atan2(
    s * @math.cos(c.gamma0) + v * @math.sin(c.gamma0),
    @math.cos(c.b_const * dlon),
  ) / c.b_const
  (u_final, vv)
}

///|
/// 由投影参数计算 Hotine 常量（含投影中心的 u 偏移）。
pub fn HotineCache::compute(
  ellipsoid : @types.Ellipsoid,
  latc : Double,
  lonc : Double,
  azimuth : Double,
  k0 : Double,
) -> HotineCache raise @types.CrsError {
  let e2 = ellipsoid.e2()
  let e = ellipsoid.e()
  let a = ellipsoid.semi_major
  let sin0 = @math.sin(latc)
  let cos0 = @math.cos(latc)
  if cos0.abs() < 1.0e-12 {
    raise @types.CrsError::Invalid("斜轴墨卡托的投影中心不能位于极点")
  }
  let cos4 = cos0 * cos0 * cos0 * cos0
  let b_const = (1.0 + e2 * cos4 / (1.0 - e2)).sqrt()
  let a_const = a * b_const * k0 * (1.0 - e2).sqrt() / (1.0 - e2 * sin0 * sin0)
  let t0 = t_func(latc, e)
  let d_const = b_const * (1.0 - e2).sqrt() / (cos0 * (1.0 - e2 * sin0 * sin0).sqrt())
  let root = (d_const * d_const - 1.0).sqrt()
  let f_const = if latc >= 0.0 {
    d_const + root
  } else {
    d_const - root
  }
  let h_const = f_const * @math.pow(t0, b_const)
  let g_const = (f_const - 1.0 / f_const) / 2.0
  let gamma0 = @math.asin(@math.sin(azimuth) / d_const)
  let lon0_prime = lonc - @math.asin(g_const * @math.tan(gamma0)) / b_const
  let partial : HotineCache = {
    b_const,
    a_const,
    d_const,
    f_const,
    h_const,
    g_const,
    gamma0,
    lon0_prime,
    u_c: 0.0,
    v_c: 0.0,
  }
  let centre = hotine_uv(partial, e, lonc, latc)
  { ..partial, u_c: centre.0, v_c: centre.1 }
}

///|
/// 正算：大地坐标（弧度）→ 平面坐标（米）。
pub fn hotine_forward(
  p : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  check_latitude(lat)
  let c = p.hotine
  let uv = hotine_uv(c, p.e, lon, lat)
  let du = uv.0 - c.u_c
  let dv = uv.1 - c.v_c
  let cg = @math.cos(p.gamma)
  let sg = @math.sin(p.gamma)
  (p.fe + dv * cg + du * sg, p.fnorth + du * cg - dv * sg)
}

///|
/// 反算：平面坐标（米）→ 大地坐标（弧度）。
pub fn hotine_inverse(
  p : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  let c = p.hotine
  let de = x - p.fe
  let dn = y - p.fnorth
  let cg = @math.cos(p.gamma)
  let sg = @math.sin(p.gamma)
  let du = dn * cg + de * sg
  let dv = de * cg - dn * sg
  let u = du + c.u_c
  let v = dv + c.v_c
  let q = @math.exp(-c.b_const * v / c.a_const)
  let s = (q - 1.0 / q) / 2.0
  let tt = (q + 1.0 / q) / 2.0
  let sin_bu = @math.sin(c.b_const * u / c.a_const)
  let ratio_u = (sin_bu * @math.cos(c.gamma0) + s * @math.sin(c.gamma0)) / tt
  if ratio_u >= 1.0 || ratio_u <= -1.0 {
    return (c.lon0_prime, p.lat0)
  }
  let arg = (1.0 + ratio_u) / (1.0 - ratio_u)
  let t = @math.pow(c.h_const / arg.sqrt(), 1.0 / c.b_const)
  let chi = pi / 2.0 - 2.0 * @math.atan(t)
  let lat = geodetic_from_conformal(chi, p.e2)
  let dlon = -@math.atan2(
    s * @math.cos(c.gamma0) - sin_bu * @math.sin(c.gamma0),
    @math.cos(c.b_const * u / c.a_const),
  ) / c.b_const
  (normalize_longitude(c.lon0_prime + dlon), lat)
}
