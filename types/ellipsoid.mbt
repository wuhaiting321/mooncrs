// 旋转椭球。
//
// 全部长度单位统一为**米**，角度内部统一为**弧度**。这是 PROJ 的约定，
// 也是所有投影公式的自然单位；只在 API 边界（用户输入、WKT 文本）出现
// 度与英尺，进来立刻归一化，避免"某处漏乘 π/180"这类经典 bug。

///|
/// 参考椭球：由长半轴 `a` 与反扁率 `1/f` 唯一确定。
///
/// 反扁率为 0 表示球体（`b = a`），用于 Web Mercator 这类球面近似投影。
pub struct Ellipsoid {
  name : String
  /// 长半轴，米。
  semi_major : Double
  /// 反扁率 1/f；0 表示球体。
  inverse_flattening : Double
} derive(Debug, Eq)

///|
pub extend Ellipsoid with @debug.Debug::{to_repr}

///|
pub extend Ellipsoid with Eq::{not_equal, equal}


///|
/// 构造椭球并做基本合法性检查。
pub fn Ellipsoid::new(
  name : String,
  semi_major : Double,
  inverse_flattening : Double,
) -> Ellipsoid raise CrsError {
  if semi_major <= 0.0 {
    raise CrsError::Invalid("椭球长半轴必须为正: " + name)
  }
  if inverse_flattening < 0.0 {
    raise CrsError::Invalid("椭球反扁率不能为负: " + name)
  }
  { name, semi_major, inverse_flattening }
}

///|
/// 短半轴 b = a(1 - f)。球体时等于 a。
pub fn Ellipsoid::semi_minor(self : Ellipsoid) -> Double {
  if self.inverse_flattening == 0.0 {
    self.semi_major
  } else {
    self.semi_major * (1.0 - 1.0 / self.inverse_flattening)
  }
}

///|
/// 扁率 f。球体为 0。
pub fn Ellipsoid::flattening(self : Ellipsoid) -> Double {
  if self.inverse_flattening == 0.0 {
    0.0
  } else {
    1.0 / self.inverse_flattening
  }
}

///|
/// 第一偏心率平方 e² = 1 - (b/a)²。
///
/// 投影公式里出现频率最高的量。这里用 b/a 计算而不是 2f - f²，
/// 因为 b/a 由 a、b 直接得到，少一次误差传播。
pub fn Ellipsoid::e2(self : Ellipsoid) -> Double {
  let ratio = self.semi_minor() / self.semi_major
  1.0 - ratio * ratio
}

///|
/// 第一偏心率 e。
pub fn Ellipsoid::e(self : Ellipsoid) -> Double {
  self.e2().sqrt()
}

///|
/// 第二偏心率平方 e'² = e²/(1-e²)。
pub fn Ellipsoid::e_prime2(self : Ellipsoid) -> Double {
  let e2 = self.e2()
  e2 / (1.0 - e2)
}

///|
/// 第三扁率 n = f/(2-f)，Krüger 级数与横轴墨卡托使用的展开变量。
pub fn Ellipsoid::third_flattening(self : Ellipsoid) -> Double {
  let f = self.flattening()
  f / (2.0 - f)
}

///|
/// 是否为球体。
pub fn Ellipsoid::is_sphere(self : Ellipsoid) -> Bool {
  self.e2() == 0.0
}

///|
/// WGS 84（EPSG:7030）。现代 GPS 与绝大多数在线地图的基准椭球。
pub let wgs84 : Ellipsoid = {
  name: "WGS 84",
  semi_major: 6378137.0,
  inverse_flattening: 298.257223563,
}

///|
/// GRS 1980（EPSG:7019）。NAD83、ETRS89、CGCS2000 使用的椭球。
pub let grs80 : Ellipsoid = {
  name: "GRS 1980",
  semi_major: 6378137.0,
  inverse_flattening: 298.257222101,
}

///|
/// CGCS2000 椭球参数与 GRS 1980 一致，这里单独命名以便注册表引用。
pub let cgcs2000 : Ellipsoid = grs80

///|
/// Airy 1830（EPSG:7001）。英国 OSGB36 使用。
pub let airy1830 : Ellipsoid = {
  name: "Airy 1830",
  semi_major: 6377563.396,
  inverse_flattening: 299.3249646,
}

///|
/// Clarke 1866（EPSG:7008）。北美 NAD27 使用。
pub let clarke1866 : Ellipsoid = {
  name: "Clarke 1866",
  semi_major: 6378206.4,
  inverse_flattening: 294.9786982,
}

///|
/// Bessel 1841（EPSG:7004）。中欧、日本、中国早期地形图使用。
pub let bessel1841 : Ellipsoid = {
  name: "Bessel 1841",
  semi_major: 6377397.155,
  inverse_flattening: 299.1528128,
}

///|
/// Krassowsky 1940（EPSG:7024）。北京 54 坐标系使用。
pub let krassowsky1940 : Ellipsoid = {
  name: "Krassowsky 1940",
  semi_major: 6378245.0,
  inverse_flattening: 298.3,
}

///|
/// 国际 1924 椭球（EPSG:7022）。ED50 等欧洲旧基准使用。
pub let intl1924 : Ellipsoid = {
  name: "International 1924",
  semi_major: 6378388.0,
  inverse_flattening: 297.0,
}

///|
/// WGS 72（EPSG:7043）。早期 GPS 与部分卫星影像使用，比 WGS84 短半轴少 1.5 m。
pub let wgs72 : Ellipsoid = {
  name: "WGS 72",
  semi_major: 6378135.0,
  inverse_flattening: 298.26,
}

///|
/// 正球（EPSG:7035）。球面近似与部分网底数据使用。
pub let normal_sphere : Ellipsoid = {
  name: "Normal Sphere",
  semi_major: 6370997.0,
  inverse_flattening: 0.0,
}

///|
/// 由长半轴与反扁率查找常用椭球；未收录时返回 `None`，由调用方决定
/// 是否降级为自定义椭球（WKT 里椭球参数总是显式给出的，所以这不是死路）。
pub fn Ellipsoid::from_name(name : String) -> Ellipsoid? {
  match name {
    "WGS 84" | "WGS84" => Some(wgs84)
    "GRS 1980" | "GRS80" => Some(grs80)
    "CGCS2000" => Some(cgcs2000)
    "Airy 1830" => Some(airy1830)
    "Clarke 1866" => Some(clarke1866)
    "Bessel 1841" => Some(bessel1841)
    "Krassowsky 1940" => Some(krassowsky1940)
    "International 1924" => Some(intl1924)
    _ => None
  }
}
