// 统一入口：一条文本 → 一个 CRS。
//
// 用户手里可能有四种东西：WKT2、WKT1、PROJ 串、EPSG 码（"EPSG:4326" 或
// 直接 "4326"）。CLI 与库函数都不该强迫用户先声明"我这是什么格式"——
// 格式判别在这里一次做掉，判别依据是各格式**不可混淆的起始特征**，
// 而不是"试着解析一遍看哪个不报错"（后者会把语法错误变成误导性的报错）。

///|
/// 解析任意格式的 CRS 定义。
pub fn parse(text : String) -> @types.Crs raise @types.CrsError {
  let trimmed = text.trim().to_owned()
  if trimmed.length() == 0 {
    raise @types.CrsError::Parse("CRS 定义为空")
  }
  match epsg_code_of(trimmed) {
    Some(code) => @epsg.get(code)
    None =>
      if looks_like_proj(trimmed) {
        parse_proj(trimmed)
      } else {
        @wkt.parse(trimmed)
      }
  }
}

///|
/// 解析 EPSG 码。
pub fn parse_epsg(code : Int32) -> @types.Crs raise @types.CrsError {
  @epsg.get(code)
}

///|
/// 解析 WKT 文本（不做格式判别）。
pub fn parse_wkt(text : String) -> @types.Crs raise @types.CrsError {
  @wkt.parse(text)
}

///|
/// 解析 PROJ 串。支持 `+init=epsg:4326` 这种"引用注册表"的写法。
pub fn parse_proj(text : String) -> @types.Crs raise @types.CrsError {
  let params = @projstr.parse(text)
  match params.get("init") {
    Some(init) =>
      match init_code(init) {
        Some(code) => @epsg.get(code)
        None =>
          raise @types.CrsError::Parse(
            "+init= 只支持 epsg:NNNN 形式，收到: " + init,
          )
      }
    None => @projstr.to_crs(params)
  }
}

///|
/// 从 "epsg:4326" 里取码。
fn init_code(text : String) -> Int32? {
  let lower = text.to_lower()
  if !has_prefix(lower, "epsg:") {
    return None
  }
  parse_int(slice(lower, 5, lower.to_array().length()))
}

///|
/// 判断一段文本是不是 EPSG 码。
///
/// 只认两种写法：`EPSG:4326` 与裸的 `4326`。不认 `urn:ogc:def:crs:EPSG::4326`
/// 这类 URN——它能表达的东西（版本、轴序覆盖）比我们支持的多，硬认下来
/// 会给出"看起来对、实际丢了语义"的结果，不如报错让用户显式转换。
fn epsg_code_of(text : String) -> Int32? {
  let lower = text.to_lower()
  if has_prefix(lower, "epsg:") {
    return parse_int(slice(lower, 5, lower.to_array().length()))
  }
  parse_int(lower)
}

///|
/// 判断是不是 PROJ 串：以 `+` 开头，或含 `+proj=`、`proj=`。
fn looks_like_proj(text : String) -> Bool {
  let lower = text.to_lower()
  has_prefix(lower, "+") ||
  contains(lower, "proj=") ||
  has_prefix(lower, "proj ")
}

///|
/// 是否为纯数字串（允许正负号）。
fn parse_int(text : String) -> Int32? {
  let chars = text.to_array()
  let n = chars.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut sign : Int32 = 1
  if chars[0] == '-' {
    sign = -1
    i = 1
  } else if chars[0] == '+' {
    i = 1
  }
  if i >= n {
    return None
  }
  let mut value : Int32 = 0
  while i < n {
    if chars[i] < '0' || chars[i] > '9' {
      return None
    }
    let digit = chars[i].to_int() - 48
    value = value * 10 + digit
    if value > 100000000 {
      return None
    }
    i = i + 1
  }
  Some(sign * value)
}

///|
/// 前缀判断。
fn has_prefix(text : String, prefix : String) -> Bool {
  let a = text.to_array()
  let b = prefix.to_array()
  if b.length() > a.length() {
    return false
  }
  let mut i = 0
  while i < b.length() {
    if a[i] != b[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 子串包含判断（区分大小写，调用方先自行转小写）。
fn contains(text : String, needle : String) -> Bool {
  let a = text.to_array()
  let b = needle.to_array()
  if b.length() > a.length() {
    return false
  }
  let mut i = 0
  while i + b.length() <= a.length() {
    let mut j = 0
    let mut hit = true
    while j < b.length() {
      if a[i + j] != b[j] {
        hit = false
        break
      }
      j = j + 1
    }
    if hit {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// 按字符下标切片。
fn slice(text : String, start : Int, stop : Int) -> String {
  let chars = text.to_array()
  let sb = StringBuilder()
  let mut i = start
  while i < stop && i < chars.length() {
    sb.write_char(chars[i])
    i = i + 1
  }
  sb.to_string()
}
