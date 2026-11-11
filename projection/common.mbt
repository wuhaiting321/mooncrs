// 投影计算的公共数学工具。
//
// 全部函数以**弧度**为角度单位、**米**为长度单位。这是 EPSG Guidance Note
// 7-2 中公式的原始单位，中间不做任何单位换算，换算只在 API 边界发生。

///|
/// π。
pub let pi : Double = 3.14159265358979323846

///|
/// 2π。
pub let two_pi : Double = 6.28318530717958647692

///|
/// 度 → 弧度。
pub fn deg2rad(d : Double) -> Double {
  d * pi / 180.0
}

///|
/// 弧度 → 度。
pub fn rad2deg(r : Double) -> Double {
  r * 180.0 / pi
}

///|
/// 角度归一化到 (-π, π]。
///
/// 投影公式对 λ-λ0 的取值敏感：跨 180° 经线时差值会跳变成 ±2π，若不归一化
/// 会得到荒谬的东坐标。所有"经度差"都必须经过这个函数。
pub fn normalize_longitude(lon : Double) -> Double {
  let mut v = lon
  while v > pi {
    v = v - two_pi
  }
  while v <= -pi {
    v = v + two_pi
  }
  v
}

///|
/// 角度归一化到 (-180, 180]（度）。
pub fn normalize_longitude_deg(lon : Double) -> Double {
  rad2deg(normalize_longitude(deg2rad(lon)))
}

///|
/// 纬度合法性检查。极点为 ±90°，超出即数据错误而非数值误差。
pub fn check_latitude(lat : Double) -> Unit raise @types.CrsError {
  if lat > pi / 2.0 + 1.0e-12 || lat < -pi / 2.0 - 1.0e-12 {
    raise @types.CrsError::Domain("纬度超出 [-90, 90] 度: " + rad2deg(lat).to_string())
  }
}

///|
/// 子午线弧长 M(φ)：从赤道到纬度 φ 的椭球子午线长度。
///
/// 采用 Snyder《Map Projections — A Working Manual》式 3-21 的八阶展开，
/// 对地球椭球在 |φ| ≤ 90° 内的截断误差约 0.1 mm，远小于本项目宣称的
/// 毫米级精度目标。
pub fn meridian_arc(a : Double, e2 : Double, lat : Double) -> Double {
  let e4 = e2 * e2
  let e6 = e4 * e2
  let e8 = e6 * e2
  let a0 = 1.0 - e2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0 - 175.0 * e8 / 16384.0
  let a2 = 3.0 * e2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0 + 105.0 * e8 / 4096.0
  let a4 = 15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0 + 525.0 * e8 / 16384.0
  let a6 = 35.0 * e6 / 3072.0 + 175.0 * e8 / 12288.0
  let a8 = 315.0 * e8 / 131072.0
  a * (a0 * lat - a2 * @math.sin(2.0 * lat) + a4 * @math.sin(4.0 * lat) -
    a6 * @math.sin(6.0 * lat) + a8 * @math.sin(8.0 * lat))
}

///|
/// 子午线弧长的导数 dM/dφ = a(1-e²)/(1-e²sin²φ)^1.5，
/// 用于由弧长反解纬度时的牛顿迭代。
pub fn meridian_arc_derivative(a : Double, e2 : Double, lat : Double) -> Double {
  let s = @math.sin(lat)
  let w = 1.0 - e2 * s * s
  a * (1.0 - e2) / (w * w.sqrt())
}

///|
/// 由子午线弧长反解纬度（牛顿迭代）。
///
/// 不用 Snyder 的 μ 级数反解，原因是级数在 |φ| 接近 90° 时精度下降，
/// 而牛顿迭代对任意纬度都稳定，且 4 次以内必收敛到 1e-15 弧度。
pub fn latitude_from_meridian_arc(
  a : Double,
  e2 : Double,
  arc : Double,
) -> Double {
  let mut lat = arc / (a * (1.0 - e2 / 4.0))
  for _ in 0..<8 {
    let diff = meridian_arc(a, e2, lat) - arc
    lat = lat - diff / meridian_arc_derivative(a, e2, lat)
  }
  lat
}

///|
/// 等角纬度辅助函数 m(φ) = cosφ / sqrt(1 - e²sin²φ)。
///
/// 几何意义：该纬度处 1 弧度经差对应的椭球面上长度与 a 之比。
pub fn m_func(lat : Double, e2 : Double) -> Double {
  let s = @math.sin(lat)
  @math.cos(lat) / (1.0 - e2 * s * s).sqrt()
}

///|
/// 等角纬度辅助函数 t(φ)：
///   t = tan(π/4 - φ/2) / [(1 - e sinφ)/(1 + e sinφ)]^(e/2)
///
/// 这是所有等角投影（Mercator、Stereographic、LCC、Oblique Mercator）
/// 的共同骨架。用 exp/ln 形式计算可以提高 φ 接近 ±90° 时的数值稳定性。
pub fn t_func(lat : Double, e : Double) -> Double {
  let s = @math.sin(lat)
  let ratio = (1.0 - e * s) / (1.0 + e * s)
  @math.tan(pi / 4.0 - lat / 2.0) / @math.pow(ratio, e / 2.0)
}

///|
/// 等角纬度 χ 的正弦值，由 t 反推：χ = π/2 - 2·atan(t)。
pub fn conformal_latitude_from_t(t : Double) -> Double {
  pi / 2.0 - 2.0 * @math.atan(t)
}

///|
/// 等角纬度 → 大地纬度（Snyder 式 3-5 的八阶反解）。
///
/// 该级数把"球面等角纬度"还原为椭球大地纬度，是 Mercator / Stereographic /
/// Oblique Mercator 反算的最后一步。八阶在整条子午线上误差 < 1e-10 弧度。
pub fn geodetic_from_conformal(chi : Double, e2 : Double) -> Double {
  let e4 = e2 * e2
  let e6 = e4 * e2
  let e8 = e6 * e2
  let c2 = e2 / 2.0 + 5.0 * e4 / 24.0 + e6 / 12.0 + 13.0 * e8 / 360.0
  let c4 = 7.0 * e4 / 48.0 + 29.0 * e6 / 240.0 + 811.0 * e8 / 11520.0
  let c6 = 7.0 * e6 / 120.0 + 81.0 * e8 / 1120.0
  let c8 = 4279.0 * e8 / 161280.0
  chi + c2 * @math.sin(2.0 * chi) + c4 * @math.sin(4.0 * chi) +
  c6 * @math.sin(6.0 * chi) + c8 * @math.sin(8.0 * chi)
}

///|
/// 由等角纬度 t 直接得到大地纬度的便捷封装。
pub fn geodetic_from_t(t : Double, e2 : Double) -> Double {
  geodetic_from_conformal(conformal_latitude_from_t(t), e2)
}

///|
/// 常量 Q = sqrt((1+e)^(1+e) · (1-e)^(1-e))。
///
/// 出现在极射赤面投影的 ρ 公式中，只与椭球有关，预先算好避免重复幂运算。
pub fn q_constant(e : Double) -> Double {
  let one_plus = 1.0 + e
  let one_minus = 1.0 - e
  let product = @math.pow(one_plus, one_plus) * @math.pow(one_minus, one_minus)
  product.sqrt()
}

///|
/// 两点间的平面距离，用于误差统计与测试。
pub fn planar_distance(x1 : Double, y1 : Double, x2 : Double, y2 : Double) -> Double {
  ((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)).sqrt()
}

///|
/// 判断两个浮点数是否在给定绝对容差内相等。
pub fn close_enough(a : Double, b : Double, tolerance : Double) -> Bool {
  (a - b).abs() <= tolerance
}

///|
/// 数值安全的除法：分母为 0 时返回 0，避免产生 NaN 静默污染结果。
pub fn safe_div(num : Double, den : Double) -> Double {
  if den == 0.0 {
    0.0
  } else {
    num / den
  }
}
