// PROJ 串语义解释：键值集合 → `Crs` 模型。
//
// 这一层是整个项目里"最不像数学、最容易出错"的部分：PROJ 的参数命名有
// 几十年的历史包袱，同一个参数在不同时期有不同写法（`+k` 与 `+k_0`、
// `+lat_ts` 与 `+lat_1`），且很多参数有 EPSG 规定的默认值。策略是
// **显式列出别名 + 显式列出默认值**，不猜、不套用"常识"。

///|
/// 由 PROJ 串构造坐标系。
///
/// 支持 `+proj=longlat`（地理）、`+proj=geocent`（地心）与 12 种投影方法。
/// 未知投影方法返回 `UnsupportedProjection` 而不是静默降级成墨卡托——
/// 静默降级会让用户拿到"看起来正常、实际错几百公里"的坐标，比报错危险得多。
pub fn to_crs(params : ProjParams) -> @types.Crs raise @types.CrsError {
  let proj = match params.get("proj") {
    Some(p) => p.to_lower()
    None => raise @types.CrsError::Parse("PROJ 串缺少 +proj 参数")
  }
  let datum = datum_of(params)
  let unit = angular_unit_of(params)
  let axis = axis_of(params, false)
  let name = crs_name(params, proj)
  if proj == "longlat" || proj == "latlong" || proj == "lonlat" {
    return @types.Crs::Geographic(
      @types.GeographicCrs::new(name, datum, unit=unit, axis=axis),
    )
  }
  if proj == "geocent" {
    return @types.Crs::Geocentric(
      @types.GeocentricCrs::new(name, datum, unit=linear_unit_of(params)),
    )
  }
  let spec = method_of(proj, params)
  let base = @types.GeographicCrs::new(
    datum.name,
    datum,
    unit=unit,
    axis=axis,
  )
  let projected_params = parameters_of(params, unit)
  @types.Crs::Projected(
    @types.ProjectedCrs::new(
      name,
      base,
      spec.0,
      projected_params,
      method_code=spec.1,
      unit=linear_unit_of(params),
      axis=axis_of(params, true),
    ),
  )
}

///|
/// 方法名与 EPSG 方法码。
fn method_of(
  proj : String,
  params : ProjParams,
) -> (String, Int32) raise @types.CrsError {
  if proj == "tmerc" || proj == "etmerc" {
    ("Transverse Mercator", 9807)
  } else if proj == "utm" {
    ("Transverse Mercator", 9807)
  } else if proj == "webmerc" {
    ("Popular Visualisation Pseudo Mercator", 1024)
  } else if proj == "merc" {
    if params.has("lat_ts") {
      ("Mercator (variant B)", 9805)
    } else {
      ("Mercator (variant A)", 9804)
    }
  } else if proj == "lcc" {
    if params.has("lat_1") && params.has("lat_2") {
      ("Lambert Conic Conformal (2SP)", 9802)
    } else {
      ("Lambert Conic Conformal (1SP)", 9801)
    }
  } else if proj == "aea" {
    ("Albers Equal Area", 9822)
  } else if proj == "omerc" {
    ("Hotine Oblique Mercator (variant B)", 9815)
  } else if proj == "stere" {
    let lat0 = params.get_double("lat_0").unwrap_or(0.0)
    if lat0.abs() > 89.0 {
      if params.has("lat_ts") {
        ("Polar Stereographic (variant B)", 9829)
      } else {
        ("Polar Stereographic (variant A)", 9810)
      }
    } else {
      // 极射赤面的赤道情形退化为正轴等角方位投影，本引擎未实现。
      raise @types.CrsError::UnsupportedProjection(
        "+proj=stere 仅支持极区（|lat_0| > 89°）",
      )
    }
  } else if proj == "cass" {
    ("Cassini-Soldner", 9806)
  } else if proj == "laea" {
    ("Lambert Azimuthal Equal Area", 9820)
  } else {
    raise @types.CrsError::UnsupportedProjection(
      "未实现的 PROJ 投影方法: +proj=" + proj,
    )
  }
}

///|
/// 参数种类，决定数值单位如何归一化。
priv enum ParamKind {
  Angle
  Length
  Scale
}

///|
/// 单个 PROJ 参数 → (EPSG 参数名, EPSG 参数码, 种类)。
///
/// 参数码取自 EPSG 数据集 6 的"Coordinate Operation Parameter"表；
/// 名称用 EPSG 官方英文名，与 WKT2 输出保持一致，方便与 pyproj 对拍。
fn param_spec(key : String) -> (String, Int32, ParamKind)? {
  match key {
    "lat_0" => Some(("Latitude of natural origin", 8801, Angle))
    "lon_0" => Some(("Longitude of natural origin", 8802, Angle))
    "k" => Some(("Scale factor at natural origin", 8805, Scale))
    "k_0" => Some(("Scale factor at natural origin", 8805, Scale))
    "x_0" => Some(("False easting", 8806, Length))
    "y_0" => Some(("False northing", 8807, Length))
    "lat_1" => Some(("Latitude of 1st standard parallel", 8823, Angle))
    "lat_2" => Some(("Latitude of 2nd standard parallel", 8824, Angle))
    "lat_ts" => Some(("Latitude of standard parallel", 8823, Angle))
    "lonc" => Some(("Longitude of projection centre", 8812, Angle))
    "lat_c" => Some(("Latitude of projection centre", 8811, Angle))
    "alpha" => Some(("Azimuth of initial line", 8813, Angle))
    "gamma" => Some(("Angle from Rectified to Skew Grid", 8814, Angle))
    _ => None
  }
}

///|
/// 把 PROJ 串里的投影参数转成 `Parameter` 数组。
///
/// `+zone`/`+south` 是 UTM 的合成参数，在这里展开成 lon_0 与 y_0，
/// 因为下游投影层只认 EPSG 语义的参数。
fn parameters_of(params : ProjParams, unit : @types.AngularUnit) -> Array[@types.Parameter] {
  let out : Array[@types.Parameter] = []
  if params.has("zone") {
    let zone = params.get_double("zone").unwrap_or(0.0)
    let lon0 = zone * 6.0 - 183.0
    out.push(
      @types.Parameter::new(
        "Longitude of natural origin",
        lon0,
        code=8802,
        unit=unit.name,
      ),
    )
    out.push(
      @types.Parameter::new(
        "Scale factor at natural origin",
        0.9996,
        code=8805,
        unit="unity",
      ),
    )
    out.push(@types.Parameter::new("False easting", 500000.0, code=8806, unit="metre"))
    let fnorth = if params.flag("south") { 10000000.0 } else { 0.0 }
    out.push(@types.Parameter::new("False northing", fnorth, code=8807, unit="metre"))
    return out
  }
  for pair in params.items {
    match param_spec(pair.0) {
      Some(spec) => {
        let value = match parse_float(pair.1) {
          Some(v) => v
          None => continue
        }
        out.push(
          @types.Parameter::new(spec.0, value, code=spec.1, unit=kind_unit(spec.2)),
        )
      }
      None => continue
    }
  }
  out
}

///|
/// 参数种类对应的单位名（仅用于展示与 WKT 输出）。
fn kind_unit(kind : ParamKind) -> String {
  match kind {
    Angle => "degree"
    Length => "metre"
    Scale => "unity"
  }
}

///|
/// 解析 `+datum=`。未给出时按 `+ellps=` 或 `+a/+b` 自建基准。
fn datum_of(params : ProjParams) -> @types.Datum raise @types.CrsError {
  let ellipsoid = ellipsoid_of(params)
  let prime_meridian = prime_meridian_of(params)
  let explicit_shift = towgs84_of(params)
  let datum_name = match params.get("datum") {
    Some(d) => d
    None => "unknown"
  }
  let shift = match explicit_shift {
    Some(h) => Some(h)
    None => default_shift(datum_name.to_upper())
  }
  let name = if datum_name == "unknown" {
    "Unknown datum based upon " + ellipsoid.name
  } else {
    datum_display_name(datum_name)
  }
  @types.Datum::new(
    name,
    ellipsoid,
    prime_meridian=prime_meridian,
    to_wgs84=shift,
  )
}

///|
/// `+datum=` 的官方全名。
///
/// PROJ 串里只有缩写（`WGS84`），但 WKT2 与 EPSG 用的是全名。
/// 若原样透传缩写，`describe` 与 `to_wkt2` 的输出就会带着
/// "WGS84" 这种不像正式名称的字符串，跨工具交换时也不便比对。
fn datum_display_name(datum : String) -> String {
  match datum.to_upper() {
    "WGS84" => "World Geodetic System 1984"
    "WGS72" => "World Geodetic System 1972"
    "NAD83" => "North American Datum 1983"
    "NAD27" => "North American Datum 1927"
    "OSGB36" => "Ordnance Survey of Great Britain 1936"
    "ETRS89" => "European Terrestrial Reference System 1989"
    "CGCS2000" => "China 2000"
    "GDA94" => "Geocentric Datum of Australia 1994"
    "POTSDAM" => "Potsdam Rauenberg 1950 DHDN"
    "CARTHAGE" => "Carthage 1934 Tunisia"
    "HERMANSKOGEL" => "Militar-Geographische Institut"
    "IRE65" => "TM65"
    "NZGD49" => "New Zealand Geodetic Datum 1949"
    "S65" => "System of the Unified Trigonometrical Cadastral Network"
    _ => datum
  }
}

///|
/// `+datum=` 的内置七参数。数值取自 EPSG 与 PROJ 的 datum 表，
/// 顺序为 dx, dy, dz, rx, ry, rz, ds（Position Vector 约定）。
fn default_shift(datum : String) -> @types.Helmert? {
  match datum {
    "WGS84" => Some(@types.helmert_identity)
    "NAD83" => Some(@types.helmert_identity)
    "ETRS89" => Some(@types.helmert_identity)
    "GDA94" => Some(@types.helmert_identity)
    "CGCS2000" => Some(@types.helmert_identity)
    "OSGB36" =>
      Some(
        @types.Helmert::new(446.448, -125.157, 542.06, 0.1502, 0.247, 0.8421, -20.4894),
      )
    "POTSDAM" =>
      Some(@types.Helmert::new(598.1, 73.7, 418.2, 0.202, 0.045, -2.455, 6.7))
    "CARTHAGE" =>
      Some(@types.Helmert::new(-263.0, 6.0, 431.0, 0.0, 0.0, 0.0, 0.0))
    "HERMANSKOGEL" =>
      Some(@types.Helmert::new(577.326, 90.129, 463.919, 5.137, 1.474, 5.297, 2.4232))
    "IRE65" =>
      Some(@types.Helmert::new(482.06, -130.71, 564.56, -2.235, 0.622, 0.624, 0.696))
    "NZGD49" =>
      Some(@types.Helmert::new(59.47, -5.04, 187.44, 0.47, -0.1, 1.024, -4.5993))
    "S65" => Some(@types.Helmert::new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0))
    _ => None
  }
}

///|
/// 解析椭球：显式 `+a/+b/+rf/+R` 优先，其次 `+ellps=` 名称表。
///
/// 顺序很关键：PROJ 允许 `+ellps=WGS84 +a=6378135` 这种覆盖写法，
/// 若先看 ellps 就会丢掉用户的显式指定。
fn ellipsoid_of(params : ProjParams) -> @types.Ellipsoid raise @types.CrsError {
  let named = match params.get("ellps") {
    Some(e) => ellipsoid_by_name(e)
    None => None
  }
  let base = match named {
    Some(e) => e
    None => @types.wgs84
  }
  if params.has("R") {
    let r = params.require_double("R")
    return @types.Ellipsoid::new("Sphere (radius " + r.to_string() + ")", r, 0.0)
  }
  let has_a = params.has("a")
  if !has_a {
    return base
  }
  let a = params.require_double("a")
  if params.has("b") {
    let b = params.require_double("b")
    let rf = a / (a - b)
    return @types.Ellipsoid::new("Custom (a=" + a.to_string() + ", b=" + b.to_string() + ")", a, rf)
  }
  if params.has("rf") {
    return @types.Ellipsoid::new(
      "Custom (a=" + a.to_string() + ", rf=" + params.get_or("rf", "0") + ")",
      a,
      params.require_double("rf"),
    )
  }
  if params.has("f") {
    let f = params.require_double("f")
    let rf = if f == 0.0 { 0.0 } else { 1.0 / f }
    return @types.Ellipsoid::new("Custom (a=" + a.to_string() + ", f=" + f.to_string() + ")", a, rf)
  }
  @types.Ellipsoid::new("Custom (a=" + a.to_string() + ", b=a)", a, 0.0)
}

///|
/// `+ellps=` 名称表。只收录真实数据里高频出现的，未命中时由 `+a/+rf` 兜底。
fn ellipsoid_by_name(name : String) -> @types.Ellipsoid? {
  match name {
    "WGS84" => Some(@types.wgs84)
    "GRS80" => Some(@types.grs80)
    "clrk66" => Some(@types.clarke1866)
    "airy" => Some(@types.airy1830)
    "bessel" => Some(@types.bessel1841)
    "krass" => Some(@types.krassowsky1940)
    "intl" => Some(@types.intl1924)
    "WGS72" => Some(@types.wgs72)
    "sphere" => Some(@types.normal_sphere)
    _ => None
  }
}

///|
/// `+pm=` 名称表与本初子午线经度（度）。
fn prime_meridian_of(params : ProjParams) -> Double {
  match params.get("pm") {
    Some(pm) =>
      match parse_float(pm) {
        Some(v) => v
        None =>
          match pm.to_lower() {
            "greenwich" => 0.0
            "lisbon" => -9.131906111
            "paris" => 2.337229167
            "bogota" => -74.080916667
            "madrid" => -3.687938889
            "rome" => 12.452333333
            "bern" => 7.439583333
            "jakarta" => 106.807719444
            "ferro" => -17.666666667
            "brussels" => 4.367975
            "stockholm" => 18.058277778
            "athens" => 23.7163375
            "oslo" => 10.722916667
            _ => 0.0
          }
      }
    None => 0.0
  }
}

///|
/// `+towgs84=dx,dy,dz[,rx,ry,rz[,ds]]`。
fn towgs84_of(params : ProjParams) -> @types.Helmert? {
  match params.get("towgs84") {
    Some(raw) => {
      let parts = split_commas(raw)
      if parts.length() < 3 {
        None
      } else {
        let v0 = parse_float(parts[0]).unwrap_or(0.0)
        let v1 = parse_float(parts[1]).unwrap_or(0.0)
        let v2 = parse_float(parts[2]).unwrap_or(0.0)
        let v3 = if parts.length() > 3 { parse_float(parts[3]).unwrap_or(0.0) } else { 0.0 }
        let v4 = if parts.length() > 4 { parse_float(parts[4]).unwrap_or(0.0) } else { 0.0 }
        let v5 = if parts.length() > 5 { parse_float(parts[5]).unwrap_or(0.0) } else { 0.0 }
        let v6 = if parts.length() > 6 { parse_float(parts[6]).unwrap_or(0.0) } else { 0.0 }
        Some(@types.Helmert::new(v0, v1, v2, v3, v4, v5, v6))
      }
    }
    None => None
  }
}

///|
/// 按逗号切分（用于 towgs84 这类内嵌列表）。
fn split_commas(raw : String) -> Array[String] {
  let out : Array[String] = []
  let mut sb = StringBuilder()
  for ch in raw {
    if ch == ',' {
      out.push(sb.to_string())
      sb = StringBuilder()
    } else {
      sb.write_char(ch)
    }
  }
  out.push(sb.to_string())
  out
}

///|
/// `+units=` → 长度单位，`+to_meter=` 可显式覆盖。
fn linear_unit_of(params : ProjParams) -> @types.LinearUnit raise @types.CrsError {
  if params.has("to_meter") {
    let factor = params.require_double("to_meter")
    return @types.LinearUnit::new("custom (" + factor.to_string() + " m)", factor)
  }
  match params.get("units") {
    Some(u) =>
      match u.to_lower() {
        "m" => @types.metre
        "km" => @types.kilometre
        "ft" => @types.foot
        "us-ft" => @types.us_survey_foot
        other => {
          let factor = match other {
            "yd" => 0.9144
            "mi" => 1609.344
            "fath" => 1.8288
            "ch" => 20.1168
            "link" => 0.201168
            "us-ch" => 20.11684023368047
            "us-mi" => 1609.347218694437
            "ind-ft" => 0.30479951024814694
            "ind-yd" => 0.9143985307444408
            _ => 1.0
          }
          @types.LinearUnit::new(other, factor)
        }
      }
    None => @types.metre
  }
}

///|
/// `+units=` 在纯地理坐标系语境下也可能给出 ang 单位；PROJ 另有
/// `+to_meter`。这里对地理坐标系固定用度（PROJ 串的约定就是度），
/// 只在显式 `+angunit` 时改。
fn angular_unit_of(params : ProjParams) -> @types.AngularUnit {
  match params.get("angunit") {
    Some(u) =>
      match @types.find_angular_unit(u) {
        Some(unit) => unit
        None => @types.degree
      }
    None => @types.degree
  }
}

///|
/// `+axis=` → 轴序。enu 是东-北-天，neu 是北-东-天。
fn axis_of(params : ProjParams, projected : Bool) -> @types.AxisOrder {
  let code = match params.get("axis") {
    Some(a) => a.to_lower()
    None => ""
  }
  if projected {
    if code == "neu" || code == "wnu" || code == "nwu" {
      @types.NorthEast
    } else {
      @types.EastNorth
    }
  } else {
    if code == "neu" || code == "nwu" || code == "wnu" {
      @types.LatLon
    } else {
      @types.LonLat
    }
  }
}

///|
/// 坐标系显示名：优先 `+title=`，否则按投影方法拼一个可读名。
fn crs_name(params : ProjParams, proj : String) -> String {
  match params.get("title") {
    Some(t) => t
    None => "PROJ " + proj
  }
}
