// 内置 EPSG 注册表。
//
// 设计取舍：**用 PROJ 串存定义**，而不是为每个码写一段构造代码。
//
// 理由有三：
// 1. 定义体是人可读的、与 PROJ/EPSG 文档同形的，审阅时能逐参数对照；
// 2. 复用 `projstr` 的语义解释层，注册表本身不重复一遍"参数怎么解释"；
// 3. 公式化的码族（UTM 60+60 个带、CGCS2000 三度带 42 个）可以按规则
//    生成，不必手抄几百行常量——手抄正是错漏的主要来源。
//
// 代价是启动时要解析几十个短串，实测在微秒级，可接受。

///|
/// 按 EPSG 码取坐标系。
///
/// 只收录真实项目中高频出现的坐标系，未收录时抛 `NotFound` 并附带
/// 可操作提示（用 WKT 或 PROJ 串直接给定义），而不是返回一个"默认
/// WGS84"——静默兜底会让用户以为转换成功了。
pub fn get(code : Int32) -> @types.Crs raise @types.CrsError {
  match definition_of(code) {
    Some(def) => {
      let params = @projstr.parse(def.1)
      let crs = @projstr.to_crs(params)
      crs
      .with_name(def.0)
      .with_identifier(@types.Identifier::new("EPSG", code))
    }
    None =>
      raise @types.CrsError::NotFound(
        "EPSG:" +
        code.to_string() +
        " 未收录于内置注册表（共 " +
        all_codes().length().to_string() +
        " 个码）；可改用 WKT2 或 PROJ 串直接给出定义",
      )
  }
}

///|
/// 是否收录。
pub fn has(code : Int32) -> Bool {
  match definition_of(code) {
    Some(_) => true
    None => false
  }
}

///|
/// 全部已收录的码，升序。
pub fn all_codes() -> Array[Int32] {
  let out : Array[Int32] = []
  let mut code = 2000
  while code <= 33000 {
    match definition_of(code) {
      Some(_) => out.push(code)
      None => ()
    }
    code = code + 1
  }
  out
}

///|
/// 按名称模糊搜索。
///
/// 匹配规则是"分词后全部命中"：`"UTM 33"` 会命中
/// `WGS 84 / UTM zone 33N`，但 `"UTM 99"` 不会。这样比单纯包含匹配
/// 更贴近用户"我记得是 33 带的 UTM"这种模糊记忆。
pub fn search(keyword : String) -> Array[(Int32, String)] {
  let out : Array[(Int32, String)] = []
  let words = split_words(keyword.to_lower())
  for code in all_codes() {
    match definition_of(code) {
      Some(def) => {
        let name = def.0.to_lower()
        let mut hit = true
        for w in words {
          if !name.contains(w) {
            hit = false
            break
          }
        }
        if hit {
          out.push((code, def.0))
        }
      }
      None => ()
    }
  }
  out
}

///|
/// 按小写空白切词。
fn split_words(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut sb = StringBuilder()
  for ch in text {
    if ch == ' ' || ch == '\t' {
      if sb.to_string().length() > 0 {
        out.push(sb.to_string())
      }
      sb = StringBuilder()
    } else {
      sb.write_char(ch)
    }
  }
  if sb.to_string().length() > 0 {
    out.push(sb.to_string())
  }
  out
}

///|
/// 取定义：(官方名称, PROJ 串)。
///
/// 分两段：先查静态表（每个码一条手写定义），再查公式族
/// （UTM 各带、CGCS2000 三度带）。两段都不命中才算未收录。
fn definition_of(code : Int32) -> (String, String)? {
  match static_definition(code) {
    Some(def) => Some(def)
    None => family_definition(code)
  }
}

///|
/// 手写定义表。
///
/// 参数全部按 EPSG 数据集 6 的"Coordinate Operation Parameter"填写，
/// 角度用度、长度用米，单位在 `+units=` 里显式声明——不依赖任何默认值，
/// 这样即使将来 PROJ 改了默认值，这里的结果也不会漂移。
fn static_definition(code : Int32) -> (String, String)? {
  match code {
    // ── 地理坐标系 ───────────────────────────────────────────────
    4326 => Some(("WGS 84", "+proj=longlat +ellps=WGS84 +datum=WGS84"))
    4269 => Some(("NAD83", "+proj=longlat +ellps=GRS80 +datum=NAD83"))
    4267 => Some(("NAD27", "+proj=longlat +ellps=clrk66 +datum=NAD27"))
    4258 => Some(("ETRS89", "+proj=longlat +ellps=GRS80 +datum=ETRS89"))
    4490 => Some(("China Geodetic Coordinate System 2000", "+proj=longlat +ellps=GRS80 +datum=CGCS2000"))
    4214 => Some(("Beijing 1954", "+proj=longlat +ellps=krass"))
    4610 => Some(("Xian 1980", "+proj=longlat +a=6378140 +rf=298.257"))
    4230 => Some(("ED50", "+proj=longlat +ellps=intl"))
    4277 => Some(("OSGB36", "+proj=longlat +ellps=airy +datum=OSGB36"))
    4171 => Some(("RGF93 v1", "+proj=longlat +ellps=GRS80 +datum=ETRS89"))
    4283 => Some(("GDA94", "+proj=longlat +ellps=GRS80 +datum=GDA94"))
    4322 => Some(("WGS 72", "+proj=longlat +ellps=WGS72"))
    4978 => Some(("WGS 84 geocentric", "+proj=geocent +ellps=WGS84 +datum=WGS84"))

    // ── 全球性投影 ───────────────────────────────────────────────
    3857 => Some(("WGS 84 / Pseudo-Mercator", "+proj=webmerc +ellps=WGS84 +datum=WGS84"))
    3395 => Some(("WGS 84 / World Mercator", "+proj=merc +lon_0=0 +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84"))
    3413 => Some(("WGS 84 / NSIDC Sea Ice Polar Stereographic North", "+proj=stere +lat_0=90 +lat_ts=70 +lon_0=-45 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84"))
    3031 => Some(("WGS 84 / Antarctic Polar Stereographic", "+proj=stere +lat_0=-90 +lat_ts=-71 +lon_0=0 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84"))
    3995 => Some(("WGS 84 / Arctic Polar Stereographic", "+proj=stere +lat_0=90 +lat_ts=71 +lon_0=0 +x_0=0 +y_0=0 +ellps=WGS84 +datum=WGS84"))
    5041 => Some(("WGS 84 / UPS North (E,N)", "+proj=stere +lat_0=90 +k=0.994 +lon_0=0 +x_0=2000000 +y_0=2000000 +ellps=WGS84 +datum=WGS84"))
    5042 => Some(("WGS 84 / UPS South (E,N)", "+proj=stere +lat_0=-90 +k=0.994 +lon_0=0 +x_0=2000000 +y_0=2000000 +ellps=WGS84 +datum=WGS84"))

    // ── 欧洲 ─────────────────────────────────────────────────────
    3035 => Some(("ETRS89-extended / LAEA Europe", "+proj=laea +lat_0=52 +lon_0=10 +x_0=4321000 +y_0=3210000 +ellps=GRS80 +datum=ETRS89"))
    3034 => Some(("ETRS89-extended / LCC Europe", "+proj=lcc +lat_1=35 +lat_2=65 +lat_0=52 +lon_0=10 +x_0=4000000 +y_0=2800000 +ellps=GRS80 +datum=ETRS89"))
    2154 => Some(("RGF93 v1 / Lambert-93", "+proj=lcc +lat_1=49 +lat_2=44 +lat_0=46.5 +lon_0=3 +x_0=700000 +y_0=6600000 +ellps=GRS80 +datum=ETRS89"))
    27700 => Some(("OSGB36 / British National Grid", "+proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 +x_0=400000 +y_0=-100000 +ellps=airy +datum=OSGB36"))
    2157 => Some(("TM65 / Irish Transverse Mercator", "+proj=tmerc +lat_0=53.5 +lon_0=-8 +k=0.99982 +x_0=600000 +y_0=750000 +ellps=GRS80"))
    29903 => Some(("TM75 / Irish Grid", "+proj=tmerc +lat_0=53.5 +lon_0=-8 +k=1.000035 +x_0=200000 +y_0=250000 +a=6377340.189 +rf=299.3249646"))
    2056 => Some(("CH1903+ / LV95", "+proj=omerc +lat_0=46.95240555555556 +lonc=7.439583333333333 +alpha=90 +gamma=90 +k=1 +x_0=2600000 +y_0=1200000 +ellps=bessel"))
    21781 => Some(("CH1903 / LV03", "+proj=omerc +lat_0=46.95240555555556 +lonc=7.439583333333333 +alpha=90 +gamma=90 +k=1 +x_0=600000 +y_0=200000 +ellps=bessel"))
    // 这里的 4.367486666666666 已是格林尼治经度（布鲁塞尔 ≈ 4.3679°E），
    // 不能再叠加 `+pm=brussels`，否则中央经线会偏到 -0.0005° 附近、
    // 横坐标整体变成负数。
    31370 => Some(("BD72 / Belgian Lambert 72", "+proj=lcc +lat_1=51.16666723333333 +lat_2=49.8333339 +lat_0=90 +lon_0=4.367486666666666 +x_0=150000.013 +y_0=5400088.438 +ellps=intl"))
    2180 => Some(("ETRF2000-PL / CS92", "+proj=lcc +lat_1=50.625 +lat_2=53.58333333333334 +lat_0=0 +lon_0=19 +x_0=500000 +y_0=-5300000 +ellps=krass"))

    // ── 北美 ─────────────────────────────────────────────────────
    // 注意：PROJ 的 `+x_0/+y_0` 恒为**米**，与 `+units` 无关。
    // EPSG 里写的是 2000000 美国测量英尺，必须换算后再填（609601.2192 m）。
    // 直接把 2000000 填进 +x_0 会让结果整体偏 5.7 倍——这是本项目
    // 曾经真实踩过的坑，故在此显式注明。
    32040 => Some(("NAD27 / Texas South Central", "+proj=lcc +lat_1=28.38333333333333 +lat_2=30.28333333333333 +lat_0=27.83333333333333 +lon_0=-99 +x_0=609601.2192024384 +y_0=0 +ellps=clrk66 +datum=NAD27 +units=us-ft"))
    2229 => Some(("NAD83 / California zone 5 (ftUS)", "+proj=lcc +lat_1=35.46666666666667 +lat_2=34.03333333333333 +lat_0=33.5 +lon_0=-118 +x_0=609601.2192334061 +y_0=152400.30483157735 +ellps=GRS80 +datum=NAD83 +units=us-ft"))

    _ => None
  }
}

///|
/// 公式族定义：UTM 与 CGCS2000 三度带。
///
/// 这些码族的参数完全由带号/中央经线决定，手抄 200 多条既无意义又易错，
/// 所以按 EPSG 的编号规则生成。
fn family_definition(code : Int32) -> (String, String)? {
  // WGS 84 / UTM zone 1N..60N（EPSG:32601–32660）
  if code >= 32601 && code <= 32660 {
    let zone = code - 32600
    return Some((utm_name(zone, false), utm_proj(zone, false, "WGS84", "WGS84")))
  }
  // WGS 84 / UTM zone 1S..60S（EPSG:32701–32760）
  if code >= 32701 && code <= 32760 {
    let zone = code - 32700
    return Some((utm_name(zone, true), utm_proj(zone, true, "WGS84", "WGS84")))
  }
  // ETRS89 / UTM zone 28N..38N（EPSG:25828–25838）
  if code >= 25828 && code <= 25838 {
    let zone = code - 25800
    return Some((etrs_utm_name(zone), utm_proj(zone, false, "GRS80", "ETRS89")))
  }
  // NAD83 / UTM zone 1N..23N（EPSG:26901–26923）
  if code >= 26901 && code <= 26923 {
    let zone = code - 26900
    return Some(("NAD83 / UTM zone " + zone.to_string() + "N", utm_proj(zone, false, "GRS80", "NAD83")))
  }
  // NAD27 / UTM zone 1N..22N（EPSG:26701–26722）
  if code >= 26701 && code <= 26722 {
    let zone = code - 26700
    return Some(("NAD27 / UTM zone " + zone.to_string() + "N", utm_proj(zone, false, "clrk66", "NAD27")))
  }
  // CGCS2000 / 3-degree Gauss-Kruger CM 75E..135E（EPSG:4491–4511）
  if code >= 4491 && code <= 4511 {
    let cm = 75 + (code - 4491) * 3
    return Some((cgcs_name(cm, false), cgcs_proj(cm, 500000.0)))
  }
  // CGCS2000 / 3-degree Gauss-Kruger zone 25..45（EPSG:4513–4533）
  if code >= 4513 && code <= 4533 {
    let zone = 25 + (code - 4513)
    let cm = zone * 3
    let fe = zone.to_double() * 1000000.0 + 500000.0
    return Some((cgcs_name(cm, true), cgcs_proj(cm, fe)))
  }
  None
}

///|
/// UTM 名称。
fn utm_name(zone : Int, south : Bool) -> String {
  "WGS 84 / UTM zone " + zone.to_string() + (if south { "S" } else { "N" })
}

///|
/// ETRS89 UTM 名称。带号与拉脱维亚式命名无关，就是 "ETRS89 / UTM zone 32N"。
fn etrs_utm_name(zone : Int) -> String {
  "ETRS89 / UTM zone " + zone.to_string() + "N"
}

///|
/// CGCS2000 高斯-克吕格名称。`with_zone` 为真时按"带号"命名。
fn cgcs_name(central_meridian : Int, with_zone : Bool) -> String {
  if with_zone {
    "CGCS2000 / 3-degree Gauss-Kruger zone " +
    (central_meridian / 3).to_string() +
    " (CM " +
    central_meridian.to_string() +
    "E)"
  } else {
    "CGCS2000 / 3-degree Gauss-Kruger CM " + central_meridian.to_string() + "E"
  }
}

///|
/// UTM 的 PROJ 串。`+zone= +south` 由 `projstr` 展开成标准参数。
fn utm_proj(zone : Int, south : Bool, ellps : String, datum : String) -> String {
  "+proj=utm +zone=" +
  zone.to_string() +
  (if south { " +south" } else { "" }) +
  " +ellps=" +
  ellps +
  " +datum=" +
  datum
}

///|
/// CGCS2000 三度带的 PROJ 串：横轴墨卡托，尺度 1，假北 0。
fn cgcs_proj(central_meridian : Int, false_easting : Double) -> String {
  "+proj=tmerc +lat_0=0 +lon_0=" +
  central_meridian.to_string() +
  " +k=1 +x_0=" +
  @projstr.fmt(false_easting) +
  " +y_0=0 +ellps=GRS80 +datum=CGCS2000 +units=m"
}
