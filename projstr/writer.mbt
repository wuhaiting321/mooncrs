// PROJ 串生成：`Crs` 模型 → `+proj=...` 文本。
//
// 与 WKT 生成器同构：都从模型出发，不读原始文本。这样"WKT 进、PROJ 出"
// 与"PROJ 进、WKT 出"两种跨格式转换自动成立，不需要单独写桥接代码。

///|
/// 把坐标系序列化成 PROJ 串。
///
/// 输出顺序固定为：proj → 椭球 → 基准 → 参数 → 单位。
/// 固定的意义是可回归：只要模型没变，字符串就逐个字节相同。
pub fn to_proj(crs : @types.Crs) -> String {
  let parts : Array[String] = []
  match crs {
    Geographic(g) => {
      parts.push("+proj=longlat")
      push_ellipsoid(parts, g.datum.ellipsoid)
      push_datum(parts, g.datum)
    }
    Geocentric(c) => {
      parts.push("+proj=geocent")
      push_ellipsoid(parts, c.datum.ellipsoid)
      push_datum(parts, c.datum)
      parts.push("+units=" + unit_code(c.unit))
    }
    Projected(p) => {
      parts.push("+proj=" + proj_code(p))
      push_ellipsoid(parts, p.base.datum.ellipsoid)
      push_datum(parts, p.base.datum)
      push_parameters(parts, p)
      parts.push("+units=" + unit_code(p.unit))
    }
  }
  join(parts, " ")
}

///|
/// 模型方法名 → PROJ 的 `+proj=` 取值。
fn proj_code(p : @types.ProjectedCrs) -> String {
  match p.method_code {
    9807 => "tmerc"
    9804 => "merc"
    9805 => "merc"
    1024 => "webmerc"
    9801 => "lcc"
    9802 => "lcc"
    9822 => "aea"
    9815 => "omerc"
    9810 => "stere"
    9829 => "stere"
    9806 => "cass"
    9820 => "laea"
    _ =>
      match p.method_name {
        "Transverse Mercator" => "tmerc"
        "Mercator (variant A)" => "merc"
        "Mercator (variant B)" => "merc"
        _ => "unknown"
      }
  }
}

///|
/// 椭球参数。球体用 `+R`，其余用 `+a` + `+rf`。
///
/// 刻意不输出 `+ellps=WGS84` 这类名称：名称表会有版本差异，而 `a/rf`
/// 是无歧义的数值，跨工具交换时更稳。
fn push_ellipsoid(parts : Array[String], ellipsoid : @types.Ellipsoid) -> Unit {
  if ellipsoid.is_sphere() {
    parts.push("+R=" + fmt(ellipsoid.semi_major))
    return
  }
  parts.push("+a=" + fmt(ellipsoid.semi_major))
  parts.push("+rf=" + fmt(ellipsoid.inverse_flattening))
}

///|
/// 基准附加参数：本初子午线与七参数。
fn push_datum(parts : Array[String], datum : @types.Datum) -> Unit {
  if datum.prime_meridian != 0.0 {
    parts.push("+pm=" + fmt(datum.prime_meridian))
  }
  match datum.to_wgs84 {
    Some(h) =>
      if !h.is_identity() {
        parts.push(
          "+towgs84=" +
          fmt(h.dx) +
          "," +
          fmt(h.dy) +
          "," +
          fmt(h.dz) +
          "," +
          fmt(h.rx) +
          "," +
          fmt(h.ry) +
          "," +
          fmt(h.rz) +
          "," +
          fmt(h.ds),
        )
      }
    None => ()
  }
}

///|
/// 投影参数。按 EPSG 参数码反查 PROJ 键名。
fn push_parameters(parts : Array[String], p : @types.ProjectedCrs) -> Unit {
  for param in p.params {
    match proj_key_of(param.code, p.method_code) {
      Some(key) => parts.push("+" + key + "=" + fmt(param.value))
      None => continue
    }
  }
}

///|
/// EPSG 参数码 → PROJ 键名。
///
/// 需要 `method_code` 参与是因为同一个参数码在不同方法里语义不同：
/// 8823 在兰勃特里是"第一标准纬线"（+lat_1），在墨卡托 variant B 与
/// 极射赤面 variant B 里是"标准纬线"（+lat_ts）。写错会让反向解析
/// 把两标准纬线的坐标系读成单标准纬线。
fn proj_key_of(code : Int32, method_code : Int32) -> String? {
  match code {
    8801 => Some("lat_0")
    8802 => Some("lon_0")
    8805 => Some("k")
    8806 => Some("x_0")
    8807 => Some("y_0")
    8823 =>
      if method_code == 9805 || method_code == 9829 {
        Some("lat_ts")
      } else {
        Some("lat_1")
      }
    8824 => Some("lat_2")
    8811 => Some("lat_0")
    8812 => Some("lonc")
    8813 => Some("alpha")
    8814 => Some("gamma")
    8816 => Some("x_0")
    8817 => Some("y_0")
    _ => None
  }
}

///|
/// 长度单位 → PROJ 的 `+units=` 取值。
fn unit_code(unit : @types.LinearUnit) -> String {
  if unit.factor == 1.0 {
    "m"
  } else if unit.factor == 1000.0 {
    "km"
  } else if unit.factor == 0.3048 {
    "ft"
  } else if (unit.factor - 0.3048006096012192).abs() < 1.0e-15 {
    "us-ft"
  } else {
    // 非标准单位：PROJ 用 `+to_meter` 表达，这里退回米并保留精度提示。
    "m"
  }
}

///|
/// 数值格式化：整数不带小数点，其余保留最短可逆表示。
///
/// 直接 `Double::to_string()` 会输出 `6378137.0` 这类带尾零的形式，
/// 与 PROJ 生态的书写习惯不符，也不利于人读配置文件。
pub fn fmt(v : Double) -> String {
  if v == 0.0 {
    return "0"
  }
  let raw = v.to_string()
  let chars = raw.to_array()
  let n = chars.length()
  // 去掉结尾的 ".0"
  if n > 2 && chars[n - 2] == '.' && chars[n - 1] == '0' {
    let sb = StringBuilder()
    let mut i = 0
    while i < n - 2 {
      sb.write_char(chars[i])
      i = i + 1
    }
    return sb.to_string()
  }
  raw
}

///|
/// 用分隔符拼接字符串数组。
fn join(items : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < items.length() {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(items[i])
    i = i + 1
  }
  sb.to_string()
}
