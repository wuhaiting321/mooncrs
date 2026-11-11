// 单位。
//
// 用"名称 + 换算因子"表示而不是固定枚举，原因是 WKT 允许任意自定义单位
// （UNIT["metre",1]、UNIT["US survey foot",0.3048006096012192]），
// 枚举无法表达"某国 1950 年的特殊英尺"。因子语义固定为
// 「1 个该单位 = factor 个基准单位」：
//   - 角度：基准是弧度
//   - 长度：基准是米

///|
/// 角度单位。`factor` 表示 1 单位等于多少弧度。
pub(all) struct AngularUnit {
  name : String
  factor : Double
} derive(Debug, Eq)

///|
pub extend AngularUnit with @debug.Debug::{to_repr}

///|
pub extend AngularUnit with Eq::{not_equal, equal}


///|
/// 长度单位。`factor` 表示 1 单位等于多少米。
pub(all) struct LinearUnit {
  name : String
  factor : Double
} derive(Debug, Eq)

///|
pub extend LinearUnit with @debug.Debug::{to_repr}

///|
pub extend LinearUnit with Eq::{not_equal, equal}


///|
/// 度。绝大多数地理坐标系使用的单位。
pub let degree : AngularUnit = { name: "degree", factor: 0.017453292519943295 }

///|
/// 弧度。
pub let radian : AngularUnit = { name: "radian", factor: 1.0 }

///|
/// 百分度（grad）。法国旧测量体系使用。
pub let grad : AngularUnit = { name: "grad", factor: 0.015707963267948967 }

///|
/// 米。
pub let metre : LinearUnit = { name: "metre", factor: 1.0 }

///|
/// 国际英尺（0.3048 m 精确值）。
pub let foot : LinearUnit = { name: "foot", factor: 0.3048 }

///|
/// 美国测量英尺。注意它与国际英尺差 2 ppm，NAD27 系列坐标系全用它，
/// 混用会造成数十米级偏移——这是 GIS 领域最经典的踩坑点之一。
pub let us_survey_foot : LinearUnit = {
  name: "US survey foot",
  factor: 0.3048006096012192,
}

///|
/// 公里。
pub let kilometre : LinearUnit = { name: "kilometre", factor: 1000.0 }

///|
/// 构造自定义角度单位。因子必须为正。
pub fn AngularUnit::new(name : String, factor : Double) -> AngularUnit raise CrsError {
  if factor <= 0.0 {
    raise CrsError::Invalid("角度单位因子必须为正: " + name)
  }
  { name, factor }
}

///|
/// 构造自定义长度单位。因子必须为正。
pub fn LinearUnit::new(name : String, factor : Double) -> LinearUnit raise CrsError {
  if factor <= 0.0 {
    raise CrsError::Invalid("长度单位因子必须为正: " + name)
  }
  { name, factor }
}

///|
/// 角度值 → 弧度。
pub fn AngularUnit::to_radians(self : AngularUnit, value : Double) -> Double {
  value * self.factor
}

///|
/// 弧度 → 角度值。
pub fn AngularUnit::from_radians(self : AngularUnit, radians : Double) -> Double {
  radians / self.factor
}

///|
/// 长度值 → 米。
pub fn LinearUnit::to_metres(self : LinearUnit, value : Double) -> Double {
  value * self.factor
}

///|
/// 米 → 长度值。
pub fn LinearUnit::from_metres(self : LinearUnit, metres : Double) -> Double {
  metres / self.factor
}

///|
/// 按 WKT 单位名猜测标准角度单位；未知名称返回 `None`。
pub fn find_angular_unit(name : String) -> AngularUnit? {
  let lower = name.to_lower()
  if lower.contains("degree") {
    Some(degree)
  } else if lower.contains("radian") {
    Some(radian)
  } else if lower.contains("grad") {
    Some(grad)
  } else {
    None
  }
}

///|
/// 按 WKT 单位名猜测标准长度单位；未知名称返回 `None`。
pub fn find_linear_unit(name : String) -> LinearUnit? {
  let lower = name.to_lower()
  if lower.contains("metre") || lower.contains("meter") {
    Some(metre)
  } else if lower.contains("kilometre") || lower.contains("kilometer") {
    Some(kilometre)
  } else if lower.contains("us survey foot") {
    Some(us_survey_foot)
  } else if lower.contains("foot") || lower.contains("feet") {
    Some(foot)
  } else {
    None
  }
}
