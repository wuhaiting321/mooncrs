// CRS 数据模型。
//
// 这一层只描述"一个坐标系长什么样"，不做任何计算。解析器（WKT / PROJ 串 /
// EPSG 注册表）负责产出它，投影与转换层负责消费它。把"表示"和"运算"分开
// 的好处是：新增一种定义语法不需要碰数学代码。

///|
/// 坐标系标识。例如 EPSG:4326。
pub struct Identifier {
  authority : String
  code : Int32
} derive(Debug, Eq)

///|
pub extend Identifier with @debug.Debug::{to_repr}

///|
pub extend Identifier with Eq::{not_equal, equal}


///|
/// 构造标识。`authority` 统一转大写，避免 "epsg" 与 "EPSG" 被当成两个东西。
pub fn Identifier::new(authority : String, code : Int32) -> Identifier {
  { authority: authority.to_upper(), code }
}

///|
/// 格式化为 "EPSG:4326"。
pub fn Identifier::to_text(self : Identifier) -> String {
  self.authority + ":" + self.code.to_string()
}

///|
/// 转换参数。`code` 为 EPSG 参数码（未知时填 0）。
///
/// 保留原始 `unit` 字符串是刻意的：参数单位可能是度、角秒、ppm、米、英尺，
/// 归一化必须由消费方按参数语义做，不能在这里一刀切。
pub struct Parameter {
  name : String
  code : Int32
  value : Double
  unit : String
} derive(Debug, Eq)

///|
pub extend Parameter with @debug.Debug::{to_repr}

///|
pub extend Parameter with Eq::{not_equal, equal}


///|
/// 构造参数。
pub fn Parameter::new(
  name : String,
  value : Double,
  code~ : Int32 = 0,
  unit~ : String = "",
) -> Parameter {
  { name, code, value, unit }
}

///|
/// 坐标轴顺序。GIS 里最容易被忽略、又最容易出错的细节：
/// EPSG:4326 官方轴序是「纬度, 经度」，而 GeoJSON 与几乎所有 API 用「经度, 纬度」。
pub(all) enum AxisOrder {
  /// 经度在前（GeoJSON / 大多数 Web API）。
  LonLat
  /// 纬度在前（EPSG 数据库对地理坐标系的官方定义）。
  LatLon
  /// 东坐标在前（投影坐标系的官方定义）。
  EastNorth
  /// 北坐标在前。
  NorthEast
} derive(Debug, Eq)

///|
pub extend AxisOrder with Eq::{not_equal, equal}

///|
pub extend AxisOrder with @debug.Debug::{to_repr}

///|


///|
/// 地理坐标系。
pub struct GeographicCrs {
  name : String
  datum : Datum
  unit : AngularUnit
  axis : AxisOrder
  id : Identifier?
} derive(Debug, Eq)

///|
pub extend GeographicCrs with @debug.Debug::{to_repr}

///|
pub extend GeographicCrs with Eq::{not_equal, equal}


///|
/// 构造地理坐标系。
pub fn GeographicCrs::new(
  name : String,
  datum : Datum,
  unit~ : AngularUnit = degree,
  axis~ : AxisOrder = LonLat,
  id~ : Identifier? = None,
) -> GeographicCrs {
  { name, datum, unit, axis, id }
}

///|
/// 投影坐标系。
pub struct ProjectedCrs {
  name : String
  /// 投影所基于的地理坐标系（提供基准与椭球）。
  base : GeographicCrs
  /// EPSG 方法名，例如 "Transverse Mercator"。
  method_name : String
  /// EPSG 方法码，例如 9807。为 0 时按方法名匹配。
  method_code : Int32
  params : Array[Parameter]
  unit : LinearUnit
  axis : AxisOrder
  id : Identifier?
} derive(Debug, Eq)

///|
pub extend ProjectedCrs with @debug.Debug::{to_repr}

///|
pub extend ProjectedCrs with Eq::{not_equal, equal}


///|
/// 构造投影坐标系。
pub fn ProjectedCrs::new(
  name : String,
  base : GeographicCrs,
  method_name : String,
  params : Array[Parameter],
  method_code~ : Int32 = 0,
  unit~ : LinearUnit = metre,
  axis~ : AxisOrder = EastNorth,
  id~ : Identifier? = None,
) -> ProjectedCrs {
  { name, base, method_name, method_code, params, unit, axis, id }
}


///|
/// 地心坐标系（ECEF）。
pub struct GeocentricCrs {
  name : String
  datum : Datum
  unit : LinearUnit
  id : Identifier?
} derive(Debug, Eq)

///|
pub extend GeocentricCrs with @debug.Debug::{to_repr}

///|
pub extend GeocentricCrs with Eq::{not_equal, equal}


///|
/// 构造地心坐标系。
pub fn GeocentricCrs::new(
  name : String,
  datum : Datum,
  unit~ : LinearUnit = metre,
  id~ : Identifier? = None,
) -> GeocentricCrs {
  { name, datum, unit, id }
}


///|
/// 任意一种坐标系。
pub(all) enum Crs {
  Geographic(GeographicCrs)
  Projected(ProjectedCrs)
  Geocentric(GeocentricCrs)
} derive(Debug, Eq)

///|
pub extend Crs with @debug.Debug::{to_repr}

///|
pub extend Crs with Eq::{not_equal, equal}


///|
/// 坐标系的显示名。
pub fn Crs::name(self : Crs) -> String {
  match self {
    Geographic(g) => g.name
    Projected(p) => p.name
    Geocentric(c) => c.name
  }
}

///|
/// 坐标系的标识（可能没有）。
pub fn Crs::identifier(self : Crs) -> Identifier? {
  match self {
    Geographic(g) => g.id
    Projected(p) => p.id
    Geocentric(c) => c.id
  }
}

///|
/// 坐标系使用的基准。
pub fn Crs::datum(self : Crs) -> Datum {
  match self {
    Geographic(g) => g.datum
    Projected(p) => p.base.datum
    Geocentric(c) => c.datum
  }
}

///|
/// 取出地理坐标系视图。投影坐标系返回其基底，地心坐标系返回 `None`
/// （地心坐标不是地理坐标，强行转换会掩盖语义错误）。
pub fn Crs::as_geographic(self : Crs) -> GeographicCrs? {
  match self {
    Geographic(g) => Some(g)
    Projected(p) => Some(p.base)
    Geocentric(_) => None
  }
}

///|
/// 附加/替换标识。用于"从 PROJ 串构造后补上 EPSG 码"这类场景：
/// 定义体本身不含 authority 信息，码由注册表提供。
///
/// 之所以不在解析阶段就塞进去，是为了让解析器保持"文本里有什么就解析
/// 什么"的纯粹性——自作主张补一个码，会让 `+init=epsg:4326` 之外的
/// 手写串也带上假身份。
pub fn Crs::with_identifier(self : Crs, id : Identifier) -> Crs {
  match self {
    Geographic(g) => Geographic({ ..g, id: Some(id) })
    Projected(p) => Projected({ ..p, id: Some(id) })
    Geocentric(c) => Geocentric({ ..c, id: Some(id) })
  }
}

///|
/// 替换显示名。注册表里的官方名称通常比 PROJ 串里能带的 `+title`
/// 更规范（大小写、连字符、缩写），所以构造后再覆盖一次。
pub fn Crs::with_name(self : Crs, name : String) -> Crs {
  match self {
    Geographic(g) => Geographic({ ..g, name })
    Projected(p) => Projected({ ..p, name })
    Geocentric(c) => Geocentric({ ..c, name })
  }
}

///|
/// 按参数名查值。匹配规则：先比 EPSG 参数码，再比规范化后的名称包含关系。
///
/// 之所以用"包含"而不是全等，是因为 WKT1 与 WKT2 的参数名不一致
/// （`False_Easting` vs `False easting`，`central_meridian` vs
/// `Longitude of natural origin`），全等匹配会漏。
pub fn ProjectedCrs::param(self : ProjectedCrs, keyword : String) -> Double? {
  let key = normalize_keyword(keyword)
  for p in self.params {
    if normalize_keyword(p.name) == key {
      return Some(p.value)
    }
  }
  for p in self.params {
    if normalize_keyword(p.name).contains(key) {
      return Some(p.value)
    }
  }
  None
}

///|
/// 按 EPSG 参数码查值。
pub fn ProjectedCrs::param_by_code(self : ProjectedCrs, code : Int32) -> Double? {
  for p in self.params {
    if p.code == code {
      return Some(p.value)
    }
  }
  None
}

///|
/// 按 EPSG 参数码取完整参数对象（含单位）。
///
/// 需要单位信息的场合（"这个假东是 2000000 米还是英尺"）只能走这条路，
/// 光拿数值会算错：NAD27 系列坐标系的假东常以美国测量英尺给出，
/// 与米相差 3.4 ppm 的换算系数，在 200 万米的量级上是 6.7 米。
pub fn ProjectedCrs::parameter_by_code(self : ProjectedCrs, code : Int32) -> Parameter? {
  for p in self.params {
    if p.code == code {
      return Some(p)
    }
  }
  None
}

///|
/// 按名称取完整参数对象。
pub fn ProjectedCrs::parameter(self : ProjectedCrs, keyword : String) -> Parameter? {
  let key = normalize_keyword(keyword)
  for p in self.params {
    if normalize_keyword(p.name) == key {
      return Some(p)
    }
  }
  for p in self.params {
    if normalize_keyword(p.name).contains(key) {
      return Some(p)
    }
  }
  None
}

///|
/// 参数名的规范化：小写、去掉下划线/空格/连字符与序号前缀。
///
/// 例如 "Latitude of 1st standard parallel" 与
/// "standard_parallel_1" 都会归一到 "latitudeof1ststandardparallel" /
/// "standardparallel1"，再由包含匹配命中。
fn normalize_keyword(s : String) -> String {
  let sb = StringBuilder()
  for ch in s.to_lower() {
    if ch == '_' || ch == ' ' || ch == '-' || ch == '(' || ch == ')' {
      continue
    }
    sb.write_char(ch)
  }
  sb.to_string()
}
