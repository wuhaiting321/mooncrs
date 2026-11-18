// 大地基准。
//
// 一个基准 = 规范标识 + 名称 + 椭球 + 本初子午线。
//
// **基准本身不携带任何转换参数。** 这是 0.1 版被驳回后的结构性修正：
// 参数属于"坐标运算"（见 operation 包），因为同一个源基准到同一个目标基准
// 往往有多套运算，精度与适用范围各不相同（OSGB36 → ETRS89 至少有 7 参数
// 与 OSTN15 网格两套，前者约 2 m、后者 0.1 m）。把一套参数挂到基准上，
// 等于宣称它在全世界、全年代都成立——这在测绘上是错的。
//
// 那 WKT1 的 `TOWGS84[...]` 与 PROJ 的 `+towgs84=` 怎么办？它们挂在
// `GeographicCrs` 上，因为那是"这份定义文本自带的参数"，不是基准的属性，
// 而且没有适用范围、没有精度声明。

///|
/// 七参数 Helmert 转换的旋转符号约定。
///
/// 同一个 `(rx, ry, rz)` 在两种约定下方向相反，混用会造成约 2 倍旋转误差。
/// EPSG 9606 = Position Vector（旋转向量，常用于欧洲），
/// EPSG 9607 = Coordinate Frame（坐标框架，常用于北美）。
pub(all) enum RotationConvention {
  /// EPSG 9606：位置向量旋转。
  PositionVector
  /// EPSG 9607：坐标框架旋转。
  CoordinateFrame
} derive(Debug, Eq)

///|
pub extend RotationConvention with @debug.Debug::{to_repr}

///|
pub extend RotationConvention with Eq::{not_equal, equal}


///|
/// 七参数 Helmert 转换（EPSG 9603/9606/9607 的公共参数载体）。
///
/// 三参数是 `rx = ry = rz = ds = 0` 的特例，不必另立类型。
pub struct Helmert {
  /// X 平移，米。
  dx : Double
  /// Y 平移，米。
  dy : Double
  /// Z 平移，米。
  dz : Double
  /// X 旋转，角秒。
  rx : Double
  /// Y 旋转，角秒。
  ry : Double
  /// Z 旋转，角秒。
  rz : Double
  /// 尺度变化，ppm。
  ds : Double
  convention : RotationConvention
} derive(Debug, Eq)

///|
pub extend Helmert with @debug.Debug::{to_repr}

///|
pub extend Helmert with Eq::{not_equal, equal}


///|
/// 无转换（恒等）。
pub let helmert_identity : Helmert = {
  dx: 0.0,
  dy: 0.0,
  dz: 0.0,
  rx: 0.0,
  ry: 0.0,
  rz: 0.0,
  ds: 0.0,
  convention: PositionVector,
}

///|
/// 构造七参数转换。角度单位为角秒，尺度为 ppm，符合 EPSG 与 WKT 的
/// `TOWGS84` 约定。
pub fn Helmert::new(
  dx : Double,
  dy : Double,
  dz : Double,
  rx : Double,
  ry : Double,
  rz : Double,
  ds : Double,
  convention~ : RotationConvention = PositionVector,
) -> Helmert {
  { dx, dy, dz, rx, ry, rz, ds, convention }
}

///|
/// 是否为单位变换（全部参数为 0），可用于跳过无谓的地心往返计算。
pub fn Helmert::is_identity(self : Helmert) -> Bool {
  self.dx == 0.0 &&
  self.dy == 0.0 &&
  self.dz == 0.0 &&
  self.rx == 0.0 &&
  self.ry == 0.0 &&
  self.rz == 0.0 &&
  self.ds == 0.0
}

///|
/// 是否只含平移（三参数）。
pub fn Helmert::is_translation_only(self : Helmert) -> Bool {
  self.rx == 0.0 && self.ry == 0.0 && self.rz == 0.0 && self.ds == 0.0
}

///|
/// 大地基准。
///
/// `key` 是规范短标识（`WGS84` / `NAD27` / `OSGB36` / …），运算注册表按它
/// 匹配参数集。名称是人读的，`key` 是机器匹配的——用名称做匹配会在
/// "WGS 84" / "World Geodetic System 1984" / "WGS_1984" 之间反复翻车。
pub struct Datum {
  /// 规范标识，未知时为 `UNKNOWN`。
  key : String
  name : String
  ellipsoid : Ellipsoid
  /// 本初子午线相对格林尼治的经度，单位：度。巴黎子午线为 2.5969213 度。
  prime_meridian : Double
} derive(Debug, Eq)

///|
pub extend Datum with @debug.Debug::{to_repr}

///|
pub extend Datum with Eq::{not_equal, equal}


///|
/// 构造基准。本初子午线经度必须在 (-180, 180] 内。
pub fn Datum::new(
  key : String,
  name : String,
  ellipsoid : Ellipsoid,
  prime_meridian~ : Double = 0.0,
) -> Datum raise CrsError {
  if prime_meridian < -180.0 || prime_meridian > 180.0 {
    raise CrsError::Invalid("本初子午线经度超出范围: " + name)
  }
  { key, name, ellipsoid, prime_meridian }
}

///|
/// 基准是否已知（能被注册表识别）。
pub fn Datum::is_known(self : Datum) -> Bool {
  self.key != "UNKNOWN"
}

///|
/// 由基准名称推断规范标识。
///
/// 匹配策略是"压缩成纯大写字母数字后包含"：`WGS_1984`、`WGS 84`、
/// `World Geodetic System 1984` 都会归到 `WGS84`。不做模糊打分，
/// 命中不了就是 `UNKNOWN`——宁可不认，也不要认错基准。
pub fn Datum::key_of(name : String) -> String {
  let compact = compact_alnum(name)
  if compact.contains("WGS84") ||
    compact.contains("WGS1984") ||
    compact.contains("WORLDGEODETICSYSTEM1984") {
    "WGS84"
  } else if compact.contains("WGS72") ||
    compact.contains("WORLDGEODETICSYSTEM1972") {
    "WGS72"
  } else if compact.contains("NAD27") ||
    compact.contains("NAD1927") ||
    compact.contains("NORTHAMERICANDATUM1927") {
    "NAD27"
  } else if compact.contains("NAD83") ||
    compact.contains("NAD1983") ||
    compact.contains("NORTHAMERICANDATUM1983") {
    "NAD83"
  } else if compact.contains("ETRS89") ||
    compact.contains("EUROPEANTERRESTRIALREFERENCE") {
    "ETRS89"
  } else if compact.contains("CGCS2000") || compact.contains("CHINA2000") {
    "CGCS2000"
  } else if compact.contains("OSGB36") ||
    compact.contains("ORDNANCESURVEYOFGREATBRITAIN") {
    "OSGB36"
  } else if compact.contains("BD72") || compact.contains("BELGIAN") {
    "BD72"
  } else if compact.contains("CH1903") || compact.contains("SWISS") {
    "CH1903"
  } else if compact.contains("DHDN") ||
    compact.contains("DEUTSCHESHAUPTDREIECKSNETZ") ||
    compact.contains("POTSDAM") {
    "DHDN"
  } else if compact.contains("TM65") || compact.contains("IRE65") {
    "TM65"
  } else if compact.contains("GDA94") ||
    compact.contains("GEOCENTRICDATUMOFAUSTRALIA") {
    "GDA94"
  } else if compact.contains("RGF93") {
    "RGF93"
  } else if compact.contains("ED50") || compact.contains("EUROPEANDATUM1950") {
    "ED50"
  } else if compact.contains("XIAN1980") || compact.contains("XIAN80") {
    "XIAN80"
  } else if compact.contains("BEIJING1954") || compact.contains("BJ54") {
    "BJ54"
  } else if compact.contains("AMERSFOORT") {
    "AMERSFOORT"
  } else if compact.contains("NTF") || compact.contains("NOUVELLETRIANGULATION") {
    "NTF"
  } else {
    "UNKNOWN"
  }
}

///|
/// 压缩成纯大写字母数字，供名称匹配用。
fn compact_alnum(text : String) -> String {
  let sb = StringBuilder()
  for ch in text.to_upper() {
    let upper = ch >= 'A' && ch <= 'Z'
    let digit = ch >= '0' && ch <= '9'
    if upper || digit {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
/// WGS 84 基准（格林尼治）。
pub let wgs84_datum : Datum = {
  key: "WGS84",
  name: "World Geodetic System 1984",
  ellipsoid: wgs84,
  prime_meridian: 0.0,
}

///|
/// CGCS2000 基准（中国 2000 国家大地坐标系）。与 WGS84 在厘米级一致，
/// 但这个"一致"是一条带精度声明的坐标运算，不是硬编码的假设。
pub let cgcs2000_datum : Datum = {
  key: "CGCS2000",
  name: "China 2000",
  ellipsoid: grs80,
  prime_meridian: 0.0,
}

///|
/// OSGB36 基准（英国）。参数不在基准上，见 `operation` 包的 EPSG:1314 与 7709。
pub let osgb36_datum : Datum = {
  key: "OSGB36",
  name: "Ordnance Survey of Great Britain 1936",
  ellipsoid: airy1830,
  prime_meridian: 0.0,
}

///|
/// NAD27 基准（北美）。没有单一参数集能覆盖全美，必须按区域/网格选运算。
pub let nad27_datum : Datum = {
  key: "NAD27",
  name: "North American Datum 1927",
  ellipsoid: clarke1866,
  prime_meridian: 0.0,
}

///|
/// 两个椭球是否数值上一致（长半轴与反扁率都相同）。
///
/// 判等用严格相等而不是容差：椭球参数是定义值，差 1 米就是不同的椭球，
/// 不是"差不多"。容差判断会掩盖拼写/单位错误。
pub fn same_ellipsoid(a : Ellipsoid, b : Ellipsoid) -> Bool {
  a.semi_major == b.semi_major && a.inverse_flattening == b.inverse_flattening
}
