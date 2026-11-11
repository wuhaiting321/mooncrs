// 大地基准。
//
// 一个基准 = 椭球 + 本初子午线 + （可选）到 WGS84 的七参数转换。
// 没有七参数时，mooncrs 按"基准相同"处理（仅做椭球/投影换算），
// 这是 PROJ 在缺少 towgs84 时的近似行为，必须让调用方知情。

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

///|
/// 七参数 Helmert 转换（EPSG 9606/9607）。
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
/// 大地基准。
pub struct Datum {
  name : String
  ellipsoid : Ellipsoid
  /// 本初子午线相对格林尼治的经度，单位：度。巴黎子午线为 2.5969213 度。
  prime_meridian : Double
  /// 到 WGS84 的七参数转换；`None` 表示未提供。
  to_wgs84 : Helmert?
} derive(Debug, Eq)

///|
pub extend Datum with @debug.Debug::{to_repr}

///|
pub extend Datum with Eq::{not_equal, equal}


///|
/// 构造基准。本初子午线经度必须在 (-180, 180] 内。
pub fn Datum::new(
  name : String,
  ellipsoid : Ellipsoid,
  prime_meridian~ : Double = 0.0,
  to_wgs84~ : Helmert? = None,
) -> Datum raise CrsError {
  if prime_meridian < -180.0 || prime_meridian > 180.0 {
    raise CrsError::Invalid("本初子午线经度超出范围: " + name)
  }
  { name, ellipsoid, prime_meridian, to_wgs84 }
}

///|
/// WGS 84 基准（格林尼治，无转换）。
pub let wgs84_datum : Datum = {
  name: "World Geodetic System 1984",
  ellipsoid: wgs84,
  prime_meridian: 0.0,
  to_wgs84: Some(helmert_identity),
}

///|
/// CGCS2000 基准（中国 2000 国家大地坐标系）。与 WGS84 在厘米级一致。
pub let cgcs2000_datum : Datum = {
  name: "China 2000",
  ellipsoid: grs80,
  prime_meridian: 0.0,
  to_wgs84: Some(helmert_identity),
}

///|
/// OSGB36 基准（英国）。到 WGS84 的七参数为 EPSG 1314。
pub let osgb36_datum : Datum = {
  name: "Ordnance Survey of Great Britain 1936",
  ellipsoid: airy1830,
  prime_meridian: 0.0,
  to_wgs84: Some(
    {
      dx: 446.448,
      dy: -125.157,
      dz: 542.06,
      rx: 0.1502,
      ry: 0.247,
      rz: 0.8421,
      ds: -20.4894,
      convention: PositionVector,
    },
  ),
}

///|
/// NAD27 基准（北美）。无公开七参数，按无转换处理。
pub let nad27_datum : Datum = {
  name: "North American Datum 1927",
  ellipsoid: clarke1866,
  prime_meridian: 0.0,
  to_wgs84: None,
}

///|
/// 基准是否有可用的七参数。没有时跨基准转换只能做椭球换算，
/// 结果会有米级到百米级误差，调用方应提示用户。
pub fn Datum::has_shift(self : Datum) -> Bool {
  match self.to_wgs84 {
    Some(h) => !h.is_identity()
    None => false
  }
}
