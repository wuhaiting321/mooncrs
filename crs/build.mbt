// 从 CRS 模型构造投影器。
//
// 这一层是"数据"到"算法"的接缝：`ProjectedCrs` 只是参数袋，`Projection`
// 才是能算的机器。接缝处的难点全在**参数命名**——同一个参数在 WKT1、
// WKT2、PROJ 里有三套名字，还各有一套 EPSG 参数码。
//
// 策略：**先按 EPSG 参数码找，再按别名找**。参数码是唯一无歧义的身份；
// 别名兜底是为了兼容只给名字不给码的野生数据。

///|
/// 度 → 弧度。
let deg_to_rad : Double = 3.141592653589793 / 180.0

///|
/// 由投影坐标系构造可计算的投影器。
///
/// `method_code` 为 0 时用方法名反查（有些 WKT1 文件把 `PROJECTION` 写成
/// 别名，码表里查不到就会落到这里）。两条路都不通时报
/// `UnsupportedProjection`，附上原始方法名，方便用户判断是"没实现"还是
/// "拼错了"。
pub fn projection_of(
  p : @types.ProjectedCrs,
) -> @projection.Projection raise @types.CrsError {
  let ellipsoid = p.base.datum.ellipsoid
  let code = if p.method_code == 0 {
    @wkt.method_code_of(p.method_name)
  } else {
    p.method_code
  }
  let lon0 = angle_param(p, [8802, 8822, 8812], longitude_aliases()).unwrap_or(0.0)
  let lat0 = angle_param(p, [8801, 8821, 8811], latitude_aliases()).unwrap_or(0.0)
  let k0 = number_param(p, [8805, 8815], scale_aliases()).unwrap_or(1.0)
  let fe = length_param(p, [8806, 8825, 8816], false_easting_aliases()).unwrap_or(0.0)
  let fnorth = length_param(p, [8807, 8826, 8817], false_northing_aliases()).unwrap_or(
    0.0,
  )
  match code {
    9807 =>
      @projection.Projection::transverse_mercator(
        ellipsoid, lon0, lat0=lat0, k0=k0, fe=fe, fnorth=fnorth,
      )
    1024 => @projection.Projection::web_mercator(ellipsoid)
    9804 =>
      @projection.Projection::mercator_1sp(
        ellipsoid, lon0, lat0=lat0, k0=k0, fe=fe, fnorth=fnorth,
      )
    9805 => {
      let lat_ts = angle_param(p, [8823], standard_parallel_aliases()).unwrap_or(0.0)
      @projection.Projection::mercator_2sp(ellipsoid, lon0, lat_ts, fe=fe, fnorth=fnorth)
    }
    9801 =>
      @projection.Projection::lcc_1sp(
        ellipsoid, lon0, lat0, k0=k0, fe=fe, fnorth=fnorth,
      )
    9802 => {
      let lat1 = angle_param(p, [8823], first_parallel_aliases()).unwrap_or(0.0)
      let lat2 = angle_param(p, [8824], second_parallel_aliases()).unwrap_or(0.0)
      @projection.Projection::lcc_2sp(
        ellipsoid, lon0, lat0, lat1, lat2, fe=fe, fnorth=fnorth,
      )
    }
    9822 => {
      let lat1 = angle_param(p, [8823], first_parallel_aliases()).unwrap_or(0.0)
      let lat2 = angle_param(p, [8824], second_parallel_aliases()).unwrap_or(0.0)
      @projection.Projection::albers(
        ellipsoid, lon0, lat0, lat1, lat2, fe=fe, fnorth=fnorth,
      )
    }
    9815 => {
      let alpha = angle_param(p, [8813], azimuth_aliases()).unwrap_or(0.0)
      let gamma = angle_param(p, [8814], rectified_angle_aliases()).unwrap_or(alpha)
      @projection.Projection::hotine_oblique(
        ellipsoid, lat0, lon0, alpha, gamma, k0, fe=fe, fnorth=fnorth,
      )
    }
    9810 =>
      @projection.Projection::polar_stereographic_a(
        ellipsoid, lat0, lon0, k0=k0, fe=fe, fnorth=fnorth,
      )
    9829 => {
      let lat_ts = angle_param(p, [8823], standard_parallel_aliases()).unwrap_or(0.0)
      @projection.Projection::polar_stereographic_b(
        ellipsoid, lat_ts, lon0, fe=fe, fnorth=fnorth,
      )
    }
    9806 => @projection.Projection::cassini(ellipsoid, lon0, lat0, fe=fe, fnorth=fnorth)
    9820 => @projection.Projection::laea(ellipsoid, lon0, lat0, fe=fe, fnorth=fnorth)
    _ =>
      raise @types.CrsError::UnsupportedProjection(
        "未实现的投影方法: " +
        p.method_name +
        "（方法码 " +
        p.method_code.to_string() +
        "）",
      )
  }
}

///|
/// 按参数码查角度值，返回弧度。
fn angle_param(
  p : @types.ProjectedCrs,
  codes : Array[Int32],
  keys : Array[String],
) -> Double? {
  match raw_param(p, codes, keys) {
    Some(v) => Some(v * deg_to_rad)
    None => None
  }
}

///|
/// 按参数码查长度值，返回米。
///
/// 参数自带单位（EPSG 2229 这类"英尺坐标系 + 米参数"的组合确实存在），
/// 所以不能想当然按 CRS 的轴单位换算。
fn length_param(
  p : @types.ProjectedCrs,
  codes : Array[Int32],
  keys : Array[String],
) -> Double? {
  for code in codes {
    match p.parameter_by_code(code) {
      Some(param) => return Some(length_to_metres(param))
      None => ()
    }
  }
  for key in keys {
    match p.parameter(key) {
      Some(param) => return Some(length_to_metres(param))
      None => ()
    }
  }
  None
}

///|
/// 按参数码查无量纲值（尺度因子）。
fn number_param(
  p : @types.ProjectedCrs,
  codes : Array[Int32],
  keys : Array[String],
) -> Double? {
  raw_param(p, codes, keys)
}

///|
/// 三路查找的统一入口：先码、后名。
fn raw_param(
  p : @types.ProjectedCrs,
  codes : Array[Int32],
  keys : Array[String],
) -> Double? {
  for code in codes {
    match p.param_by_code(code) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  for key in keys {
    match find_param_by_name(p, key) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  None
}

///|
/// 按规范化名称查参数值。
fn find_param_by_name(p : @types.ProjectedCrs, key : String) -> Double? {
  match p.param(key) {
    Some(v) => Some(v)
    None => None
  }
}

///|
/// 参数值换算为米。单位缺失时按米处理（EPSG 参数的默认单位）。
fn length_to_metres(param : @types.Parameter) -> Double {
  if param.unit.length() == 0 {
    return param.value
  }
  match @types.find_linear_unit(param.unit) {
    Some(unit) => unit.to_metres(param.value)
    None => param.value
  }
}

// ── 参数别名表 ────────────────────────────────────────────────────
//
// 每张表都同时覆盖 WKT2 官方英文名、WKT1 下划线名与常见别名。
// 名称已按 `normalize_keyword` 的规则去掉空格与下划线，因此
// "False_Easting" 与 "False easting" 在这里是同一个字符串。

///|
fn longitude_aliases() -> Array[String] {
  [
    "longitudeofnaturalorigin",
    "longitudeoffalseorigin",
    "longitudeoforigin",
    "longitudeofcenter",
    "longitudeofcentre",
    "longitudeofprojectioncentre",
    "centralmeridian",
  ]
}

///|
fn latitude_aliases() -> Array[String] {
  [
    "latitudeofnaturalorigin",
    "latitudeoffalseorigin",
    "latitudeoforigin",
    "latitudeofcenter",
    "latitudeofcentre",
    "latitudeofprojectioncentre",
  ]
}

///|
fn scale_aliases() -> Array[String] {
  ["scalefactoratnaturalorigin", "scalefactoroninitialline", "scalefactor"]
}

///|
fn false_easting_aliases() -> Array[String] {
  ["falseeasting", "eastingatfalseorigin", "eastingatprojectioncentre"]
}

///|
fn false_northing_aliases() -> Array[String] {
  ["falsenorthing", "northingatfalseorigin", "northingatprojectioncentre"]
}

///|
fn first_parallel_aliases() -> Array[String] {
  ["latitudeof1ststandardparallel", "standardparallel1"]
}

///|
fn second_parallel_aliases() -> Array[String] {
  ["latitudeof2ndstandardparallel", "standardparallel2"]
}

///|
fn standard_parallel_aliases() -> Array[String] {
  ["latitudeofstandardparallel", "standardparallel"]
}

///|
fn azimuth_aliases() -> Array[String] {
  ["azimuthofinitialline", "azimuthatprojectioncentre", "azimuth"]
}

///|
fn rectified_angle_aliases() -> Array[String] {
  ["anglefromrectifiedtoskewgrid", "rectifiedgridangle", "rectifiedangle"]
}
