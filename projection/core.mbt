// 投影对象：把"方法 + 参数"组织成可调用的正算/反算器。
//
// 设计取舍：用单个 struct 承载所有方法的参数（而不是为每个方法定义独立类型
// 再放进 enum），原因是转换管道需要在运行时动态构造投影——参数来自 WKT 或
// EPSG 注册表，编译期并不知道具体是哪种方法。单 struct + 方法枚举让
// "构造 → 校验 → 计算"三步保持线性，代价是结构体略胖，但语义清晰。

///|
/// 支持的投影方法。
pub enum Method {
  Mercator1SP
  Mercator2SP
  WebMercator
  TransverseMercator
  LambertConicConformal1SP
  LambertConicConformal2SP
  AlbersEqualArea
  HotineObliqueMercator
  PolarStereographicA
  PolarStereographicB
  CassiniSoldner
  LambertAzimuthalEqualArea
} derive(Debug, Eq)

///|
pub extend Method with @debug.Debug::{to_repr}

///|
pub extend Method with Eq::{not_equal, equal}

///|
/// 投影实例。角度字段一律弧度，长度字段一律米。
pub struct Projection {
  method_kind : Method
  a : Double
  e2 : Double
  e : Double
  /// 中央经线 / 投影中心经度。
  lon0 : Double
  /// 原点纬度。
  lat0 : Double
  /// 原点尺度因子。
  k0 : Double
  /// 假东。
  fe : Double
  /// 假北。
  fnorth : Double
  /// 第一标准纬线（圆锥投影）/ 标准纬线（极射赤面 B）。
  lat1 : Double
  /// 第二标准纬线。
  lat2 : Double
  /// 初始线方位角（斜轴墨卡托）。
  azimuth : Double
  /// 整流方位角 γc（斜轴墨卡托）。
  gamma : Double
  /// 横轴墨卡托级数系数。
  series : KrugerSeries
  /// 圆锥投影公共参数 n。
  conic_n : Double
  /// 圆锥投影因子（LCC 的 F / Albers 的 C）。
  conic_factor : Double
  /// 圆锥投影原点半径 ρ0。
  conic_rho0 : Double
  /// 横轴墨卡托原点北坐标（级数从赤道起算，需减去它）。
  tm_y0 : Double
  /// 斜轴墨卡托预计算常量。
  hotine : HotineCache
} derive(Debug)

///|
pub extend Projection with @debug.Debug::{to_repr}

///|
/// 全部参数置零的骨架，仅供内部构造使用。
fn blank(
  kind : Method,
  ellipsoid : @types.Ellipsoid,
) -> Projection {
  {
    method_kind: kind,
    a: ellipsoid.semi_major,
    e2: ellipsoid.e2(),
    e: ellipsoid.e(),
    lon0: 0.0,
    lat0: 0.0,
    k0: 1.0,
    fe: 0.0,
    fnorth: 0.0,
    lat1: 0.0,
    lat2: 0.0,
    azimuth: 0.0,
    gamma: 0.0,
    series: KrugerSeries::zero(),
    conic_n: 0.0,
    conic_factor: 0.0,
    conic_rho0: 0.0,
    tm_y0: 0.0,
    hotine: HotineCache::zero(),
  }
}

///|
/// 方法名（用于报错与文档）。
pub fn Projection::method_name(self : Projection) -> String {
  match self.method_kind {
    Mercator1SP => "Mercator (variant A)"
    Mercator2SP => "Mercator (variant B)"
    WebMercator => "Popular Visualisation Pseudo Mercator"
    TransverseMercator => "Transverse Mercator"
    LambertConicConformal1SP => "Lambert Conic Conformal (1SP)"
    LambertConicConformal2SP => "Lambert Conic Conformal (2SP)"
    AlbersEqualArea => "Albers Equal Area"
    HotineObliqueMercator => "Hotine Oblique Mercator (variant B)"
    PolarStereographicA => "Polar Stereographic (variant A)"
    PolarStereographicB => "Polar Stereographic (variant B)"
    CassiniSoldner => "Cassini-Soldner"
    LambertAzimuthalEqualArea => "Lambert Azimuthal Equal Area"
  }
}

///|
/// 墨卡托（1SP）：给定原点纬度与尺度因子。
///
/// 球面与椭球统一处理：椭球时用 t(φ) 形式，球面时 e=0 自动退化为
/// 经典 ln(tan(π/4+φ/2))。
pub fn Projection::mercator_1sp(
  ellipsoid : @types.Ellipsoid,
  lon0 : Double,
  lat0~ : Double = 0.0,
  k0~ : Double = 1.0,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection raise @types.CrsError {
  if k0 <= 0.0 {
    raise @types.CrsError::Invalid("尺度因子必须为正")
  }
  let mut p = blank(Mercator1SP, ellipsoid)
  p = { ..p, lon0, lat0, k0, fe, fnorth }
  p
}

///|
/// 墨卡托（2SP）：给定第一标准纬线，尺度因子由标准纬线导出。
///
/// EPSG 9805 的定义是「在标准纬线上尺度为真」，因此
/// k0 = m(φ1) / (a 归一化) = cosφ1 / sqrt(1 - e²sin²φ1)。
pub fn Projection::mercator_2sp(
  ellipsoid : @types.Ellipsoid,
  lon0 : Double,
  lat1 : Double,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection {
  let e2 = ellipsoid.e2()
  let m1 = m_func(lat1, e2)
  let mut p = blank(Mercator2SP, ellipsoid)
  p = { ..p, lon0, lat0: 0.0, lat1, k0: m1, fe, fnorth }
  p
}

///|
/// Web Mercator（EPSG 1024，即 EPSG:3857）。
///
/// 注意：它**不是**严格意义上的椭球墨卡托，而是把球面墨卡托公式直接套在
/// WGS84 的球半径上。这正是它与 EPSG:3395 存在约 20 km 差异的原因，
/// 也是所有在线地图瓦片能对齐的前提。这里显式实现，不做椭球化"纠正"。
pub fn Projection::web_mercator(
  ellipsoid : @types.Ellipsoid,
) -> Projection {
  let mut p = blank(WebMercator, ellipsoid)
  p = { ..p, k0: 1.0 }
  p
}

///|
/// 横轴墨卡托（EPSG 9807）。
pub fn Projection::transverse_mercator(
  ellipsoid : @types.Ellipsoid,
  lon0 : Double,
  lat0~ : Double = 0.0,
  k0~ : Double = 1.0,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection raise @types.CrsError {
  if k0 <= 0.0 {
    raise @types.CrsError::Invalid("尺度因子必须为正")
  }
  let mut p = blank(TransverseMercator, ellipsoid)
  let series = KrugerSeries::new(ellipsoid)
  let y0 = krueger_origin_northing(series, ellipsoid.e(), k0, lat0)
  p = { ..p, lon0, lat0, k0, fe, fnorth, series, tm_y0: y0 }
  p
}

///|
/// UTM：横轴墨卡托的特例。
///
/// `zone` 必须在 1..60；中央经线 = zone×6 − 183 度；尺度因子 0.9996；
/// 假东 500 km；南半球假北 10000 km。
pub fn Projection::utm(
  ellipsoid : @types.Ellipsoid,
  zone : Int,
  south~ : Bool = false,
) -> Projection raise @types.CrsError {
  if zone < 1 || zone > 60 {
    raise @types.CrsError::Invalid("UTM 带号必须在 1..60，收到 " + zone.to_string())
  }
  let lon0 = deg2rad(zone.to_double() * 6.0 - 183.0)
  let fnorth = if south { 10000000.0 } else { 0.0 }
  Projection::transverse_mercator(ellipsoid, lon0, k0=0.9996, fe=500000.0, fnorth=fnorth)
}

///|
/// 兰勃特等角圆锥（1SP，EPSG 9801）。
pub fn Projection::lcc_1sp(
  ellipsoid : @types.Ellipsoid,
  lon0 : Double,
  lat0 : Double,
  k0~ : Double = 1.0,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection raise @types.CrsError {
  let e2 = ellipsoid.e2()
  let e = ellipsoid.e()
  if lat0.abs() < 1.0e-12 {
    raise @types.CrsError::Invalid("1SP 兰勃特的原点纬度不能为 0")
  }
  let n = @math.sin(lat0)
  let m0 = m_func(lat0, e2)
  let t0 = t_func(lat0, e)
  let f = m0 / (n * @math.pow(t0, n))
  let rho0 = ellipsoid.semi_major * f * @math.pow(t0, n)
  let mut p = blank(LambertConicConformal1SP, ellipsoid)
  p = {
    ..p,
    lon0,
    lat0,
    k0,
    fe,
    fnorth,
    lat1: lat0,
    conic_n: n,
    conic_factor: f * k0,
    conic_rho0: rho0 * k0,
  }
  p
}

///|
/// 兰勃特等角圆锥（2SP，EPSG 9802）。中国 1:100 万地形图与欧洲多数国家
/// 坐标系使用此方法。
pub fn Projection::lcc_2sp(
  ellipsoid : @types.Ellipsoid,
  lon0 : Double,
  lat0 : Double,
  lat1 : Double,
  lat2 : Double,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection raise @types.CrsError {
  let e2 = ellipsoid.e2()
  let e = ellipsoid.e()
  if (lat1 - lat2).abs() < 1.0e-12 {
    raise @types.CrsError::Invalid("两条标准纬线不能相同")
  }
  let m1 = m_func(lat1, e2)
  let m2 = m_func(lat2, e2)
  let t1 = t_func(lat1, e)
  let t2 = t_func(lat2, e)
  let n = (@math.ln(m1) - @math.ln(m2)) / (@math.ln(t1) - @math.ln(t2))
  let f = m1 / (n * @math.pow(t1, n))
  let t0 = t_func(lat0, e)
  let rho0 = ellipsoid.semi_major * f * @math.pow(t0, n)
  let mut p = blank(LambertConicConformal2SP, ellipsoid)
  p = {
    ..p,
    lon0,
    lat0,
    k0: 1.0,
    fe,
    fnorth,
    lat1,
    lat2,
    conic_n: n,
    conic_factor: f,
    conic_rho0: rho0,
  }
  p
}

///|
/// 阿尔伯斯等积圆锥（EPSG 9822）。中国全国性地图常用。
pub fn Projection::albers(
  ellipsoid : @types.Ellipsoid,
  lon0 : Double,
  lat0 : Double,
  lat1 : Double,
  lat2 : Double,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection raise @types.CrsError {
  let e2 = ellipsoid.e2()
  let e = ellipsoid.e()
  if (lat1 - lat2).abs() < 1.0e-12 {
    raise @types.CrsError::Invalid("两条标准纬线不能相同")
  }
  let m1 = m_func(lat1, e2)
  let m2 = m_func(lat2, e2)
  let q1 = authalic_q(lat1, e2, e)
  let q2 = authalic_q(lat2, e2, e)
  let n = (m1 * m1 - m2 * m2) / (q2 - q1)
  let c = m1 * m1 + n * q1
  let q0 = authalic_q(lat0, e2, e)
  let rho0 = ellipsoid.semi_major * (c - n * q0).sqrt() / n
  let mut p = blank(AlbersEqualArea, ellipsoid)
  p = {
    ..p,
    lon0,
    lat0,
    k0: 1.0,
    fe,
    fnorth,
    lat1,
    lat2,
    conic_n: n,
    conic_factor: c,
    conic_rho0: rho0,
  }
  p
}

///|
/// 等积纬度辅助量 q(φ)，Albers 与等积投影共用。
pub fn authalic_q(lat : Double, e2 : Double, e : Double) -> Double {
  let s = @math.sin(lat)
  let w = 1.0 - e2 * s * s
  if e < 1.0e-12 {
    2.0 * s
  } else {
    (1.0 - e2) * (s / w - (1.0 / (2.0 * e)) * @math.ln((1.0 - e * s) / (1.0 + e * s)))
  }
}

///|
/// 斜轴墨卡托（Hotine，variant B，EPSG 9815）。
///
/// 用于马来西亚 RSO、瑞士等坐标系。参数含义与 EPSG 一致：
/// `latc/lonc` 是投影中心，`azimuth` 是初始线方位角，`gamma` 是整流方位角
/// （初始线与网格北的夹角）。
pub fn Projection::hotine_oblique(
  ellipsoid : @types.Ellipsoid,
  latc : Double,
  lonc : Double,
  azimuth : Double,
  gamma : Double,
  k0 : Double,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection raise @types.CrsError {
  if k0 <= 0.0 {
    raise @types.CrsError::Invalid("尺度因子必须为正")
  }
  let cache = HotineCache::compute(ellipsoid, latc, lonc, azimuth, k0)
  let mut p = blank(HotineObliqueMercator, ellipsoid)
  p = { ..p, lon0: lonc, lat0: latc, k0, fe, fnorth, azimuth, gamma, hotine: cache }
  p
}

///|
/// 极射赤面（variant A，EPSG 9810）：给定极点与尺度因子。
pub fn Projection::polar_stereographic_a(
  ellipsoid : @types.Ellipsoid,
  lat0 : Double,
  lon0 : Double,
  k0~ : Double = 1.0,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection raise @types.CrsError {
  if (lat0.abs() - pi / 2.0).abs() > 1.0e-6 {
    raise @types.CrsError::Invalid("variant A 的原点纬度必须为 ±90°")
  }
  if k0 <= 0.0 {
    raise @types.CrsError::Invalid("尺度因子必须为正")
  }
  let mut p = blank(PolarStereographicA, ellipsoid)
  p = { ..p, lon0, lat0, k0, fe, fnorth }
  p
}

///|
/// 极射赤面（variant B，EPSG 9829）：给定标准纬线，尺度因子由其导出。
pub fn Projection::polar_stereographic_b(
  ellipsoid : @types.Ellipsoid,
  lat_ts : Double,
  lon0 : Double,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection raise @types.CrsError {
  if lat_ts.abs() < 1.0e-9 || (lat_ts.abs() - pi / 2.0).abs() < 1.0e-9 {
    raise @types.CrsError::Invalid("variant B 的标准纬线不能为 0 或 ±90°")
  }
  let e2 = ellipsoid.e2()
  let e = ellipsoid.e()
  let mf = m_func(lat_ts, e2)
  let tf = t_func(lat_ts, e)
  let k0 = mf * q_constant(e) / (2.0 * tf)
  let mut p = blank(PolarStereographicB, ellipsoid)
  p = {
    ..p,
    lon0,
    lat0: if lat_ts > 0.0 { pi / 2.0 } else { -pi / 2.0 },
    k0,
    fe,
    fnorth,
    lat1: lat_ts,
  }
  p
}

///|
/// 卡西尼-塞尔德纳（EPSG 9806）。中国 1954 北京坐标系的部分老图件使用。
pub fn Projection::cassini(
  ellipsoid : @types.Ellipsoid,
  lon0 : Double,
  lat0 : Double,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection {
  let mut p = blank(CassiniSoldner, ellipsoid)
  p = { ..p, lon0, lat0, fe, fnorth }
  p
}

///|
/// 兰勃特方位等积（EPSG 9820）。欧洲 ETRS89-LAEA（EPSG:3035）使用。
pub fn Projection::laea(
  ellipsoid : @types.Ellipsoid,
  lon0 : Double,
  lat0 : Double,
  fe~ : Double = 0.0,
  fnorth~ : Double = 0.0,
) -> Projection {
  let mut p = blank(LambertAzimuthalEqualArea, ellipsoid)
  p = { ..p, lon0, lat0, fe, fnorth }
  p
}

///|
/// 正算入口：大地坐标（弧度）→ 平面坐标（米）。
pub fn Projection::forward(
  self : Projection,
  lon : Double,
  lat : Double,
) -> (Double, Double) raise @types.CrsError {
  match self.method_kind {
    Mercator1SP | Mercator2SP => mercator_forward(self, lon, lat)
    WebMercator => web_mercator_forward(self, lon, lat)
    TransverseMercator =>
      transverse_mercator_forward(
        self.series,
        self.e,
        self.lon0,
        self.k0,
        self.fe,
        self.fnorth,
        self.tm_y0,
        lon,
        lat,
      )
    LambertConicConformal1SP | LambertConicConformal2SP => lcc_forward(self, lon, lat)
    AlbersEqualArea => albers_forward(self, lon, lat)
    HotineObliqueMercator => hotine_forward(self, lon, lat)
    PolarStereographicA | PolarStereographicB => polar_stereo_forward(self, lon, lat)
    CassiniSoldner => cassini_forward(self, lon, lat)
    LambertAzimuthalEqualArea => laea_forward(self, lon, lat)
  }
}

///|
/// 反算入口：平面坐标（米）→ 大地坐标（弧度）。
pub fn Projection::inverse(
  self : Projection,
  x : Double,
  y : Double,
) -> (Double, Double) {
  match self.method_kind {
    Mercator1SP | Mercator2SP => mercator_inverse(self, x, y)
    WebMercator => web_mercator_inverse(self, x, y)
    TransverseMercator =>
      transverse_mercator_inverse(
        self.series,
        self.e2,
        self.lon0,
        self.k0,
        self.fe,
        self.fnorth,
        self.tm_y0,
        x,
        y,
      )
    LambertConicConformal1SP | LambertConicConformal2SP => lcc_inverse(self, x, y)
    AlbersEqualArea => albers_inverse(self, x, y)
    HotineObliqueMercator => hotine_inverse(self, x, y)
    PolarStereographicA | PolarStereographicB => polar_stereo_inverse(self, x, y)
    CassiniSoldner => cassini_inverse(self, x, y)
    LambertAzimuthalEqualArea => laea_inverse(self, x, y)
  }
}

///|
/// 该投影是否适合处理给定经度范围（用于给出"超出有效范围"的告警）。
///
/// 横轴墨卡托在离中央经线 9° 以外误差迅速增大；其余投影不设限。
/// 这里只做判断，不抛错——是否接受由调用方决定。
pub fn Projection::longitude_span_ok(self : Projection, lon : Double) -> Bool {
  match self.method_kind {
    TransverseMercator => normalize_longitude(lon - self.lon0).abs() <= deg2rad(9.0)
    _ => true
  }
}
