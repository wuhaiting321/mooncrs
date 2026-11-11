// PROJ 串解析。
//
// 为什么需要单独一套解析器：WKT 是树、PROJ 串是"平铺的 +key=value 列表"，
// 语法完全不相交。而现实世界里两者混用得很厉害——PostGIS 的
// spatial_ref_sys 两种都存，GDAL 命令行只吃 PROJ 串，Shapefile 的 .prj
// 又只有 WKT。只支持一种就等于放弃一半数据源。
//
// 本模块只做"文本 → 键值集合"这一步，把语义解释留给 `build.mbt`，
// 这样生成（writer）与解释（build）可以各自独立测试。

///|
/// PROJ 串解析结果：有序键值对。
///
/// 用 `Array[(String, String)]` 而不是 `Map` 有两个理由：
/// 1. 键少（通常 5~10 个），线性查找的成本可以忽略；
/// 2. 保持输入顺序，生成时输出稳定，回归测试可以直接比对字符串。
pub struct ProjParams {
  items : Array[(String, String)]
} derive(Debug, Eq)

///|
pub extend ProjParams with @debug.Debug::{to_repr}

///|
pub extend ProjParams with Eq::{not_equal, equal}

///|
/// 构造空集合。
pub fn ProjParams::new() -> ProjParams {
  { items: [] }
}

///|
/// 写入一个键值。同名键后者覆盖前者（PROJ 的实际行为）。
pub fn ProjParams::set(self : ProjParams, key : String, value : String) -> Unit {
  let mut i = 0
  while i < self.items.length() {
    if self.items[i].0 == key {
      self.items[i] = (key, value)
      return
    }
    i = i + 1
  }
  self.items.push((key, value))
}

///|
/// 读取键值。键名区分大小写。
pub fn ProjParams::get(self : ProjParams, key : String) -> String? {
  for pair in self.items {
    if pair.0 == key {
      return Some(pair.1)
    }
  }
  None
}

///|
/// 读取键值，缺省时返回给定默认值。
pub fn ProjParams::get_or(self : ProjParams, key : String, fallback : String) -> String {
  match self.get(key) {
    Some(v) => v
    None => fallback
  }
}

///|
/// 键是否存在。
pub fn ProjParams::has(self : ProjParams, key : String) -> Bool {
  match self.get(key) {
    Some(_) => true
    None => false
  }
}

///|
/// 读取数值。缺失或无法解析时返回 `None`——注意区分"没写"和"写错了"：
/// 调用方通常对前者取 EPSG 默认值，对后者应当报错，所以这里不做合并。
pub fn ProjParams::get_double(self : ProjParams, key : String) -> Double? {
  match self.get(key) {
    Some(v) => parse_float(v)
    None => None
  }
}

///|
/// 读取数值，缺失或非法时抛错。
pub fn ProjParams::require_double(
  self : ProjParams,
  key : String,
) -> Double raise @types.CrsError {
  match self.get(key) {
    Some(v) =>
      match parse_float(v) {
        Some(x) => x
        None => raise @types.CrsError::Parse("+" + key + " 不是合法数值: " + v)
      }
    None => raise @types.CrsError::Parse("缺少必需参数 +" + key)
  }
}

///|
/// 读取"标志型"参数：`+south` 这类不带值的键存在即为真。
/// 显式写成 `+south=no` / `+south=0` 时视为假。
pub fn ProjParams::flag(self : ProjParams, key : String) -> Bool {
  match self.get(key) {
    Some(v) => {
      let lower = v.to_lower()
      !(lower == "no" || lower == "false" || lower == "0" || lower == "off")
    }
    None => false
  }
}

///|
/// 全部键名（按输入顺序）。
pub fn ProjParams::keys(self : ProjParams) -> Array[String] {
  let out : Array[String] = []
  for pair in self.items {
    out.push(pair.0)
  }
  out
}

///|
/// 解析 `+proj=... +datum=...` 形式的串。
///
/// 宽容度：允许不以 `+` 开头的片段（有些老配置写成 `proj=utm zone=50`），
/// 允许 `+key` 不带值（转成 `key -> ""`）。空串返回空集合而不是报错，
/// 由上层判断"到底有没有给参数"。
pub fn parse(text : String) -> ProjParams raise @types.CrsError {
  let params = ProjParams::new()
  let chars = text.to_array()
  let n = chars.length()
  let mut i = 0
  let mut buf = StringBuilder()
  let mut started = false
  while i <= n {
    let at_end = i == n
    let ch = if at_end { ' ' } else { chars[i] }
    if at_end || ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      if started {
        commit_token(params, buf.to_string())
        buf = StringBuilder()
        started = false
      }
    } else {
      buf.write_char(ch)
      started = true
    }
    i = i + 1
  }
  params
}

///|
/// 把一个词法单元拆成键值写进集合。
fn commit_token(params : ProjParams, token : String) -> Unit raise @types.CrsError {
  let body = strip_plus(token)
  if body.length() == 0 {
    return
  }
  let chars = body.to_array()
  let n = chars.length()
  let mut split = -1
  let mut i = 0
  while i < n {
    if chars[i] == '=' {
      split = i
      break
    }
    i = i + 1
  }
  if split < 0 {
    // 无等号：标志型参数，值记为空串。
    params.set(body, "")
    return
  }
  let key = slice(body, 0, split)
  let value = slice(body, split + 1, n)
  if key.length() == 0 {
    raise @types.CrsError::Parse("PROJ 串出现空键名: " + token)
  }
  params.set(key, value)
}

///|
/// 去掉前导 `+`。
fn strip_plus(token : String) -> String {
  let chars = token.to_array()
  if chars.length() > 0 && chars[0] == '+' {
    slice(token, 1, chars.length())
  } else {
    token
  }
}

///|
/// 按字符下标切片。
fn slice(s : String, start : Int, stop : Int) -> String {
  let chars = s.to_array()
  let sb = StringBuilder()
  let mut i = start
  while i < stop && i < chars.length() {
    sb.write_char(chars[i])
    i = i + 1
  }
  sb.to_string()
}

///|
/// 手写浮点解析：支持符号、小数、指数（`1e-5`、`-2.5E3`）。
///
/// 不直接用标准库是为了统一返回 `Option` 语义——PROJ 串里大量参数
/// 允许缺失，拿异常来区分"缺失"和"非法"会把调用方写得很啰嗦。
pub fn parse_float(raw : String) -> Double? {
  let chars = raw.to_array()
  let n = chars.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut sign = 1.0
  if chars[0] == '+' {
    i = 1
  } else if chars[0] == '-' {
    sign = -1.0
    i = 1
  }
  let mut mantissa = 0.0
  let mut digits = 0
  while i < n && chars[i] >= '0' && chars[i] <= '9' {
    mantissa = mantissa * 10.0 + (chars[i].to_int() - 48).to_double()
    digits = digits + 1
    i = i + 1
  }
  let mut scale = 1.0
  if i < n && chars[i] == '.' {
    i = i + 1
    while i < n && chars[i] >= '0' && chars[i] <= '9' {
      mantissa = mantissa * 10.0 + (chars[i].to_int() - 48).to_double()
      scale = scale * 10.0
      digits = digits + 1
      i = i + 1
    }
  }
  if digits == 0 {
    return None
  }
  let mut value = mantissa / scale
  if i < n && (chars[i] == 'e' || chars[i] == 'E') {
    i = i + 1
    let mut esign = 1.0
    if i < n && (chars[i] == '+' || chars[i] == '-') {
      if chars[i] == '-' {
        esign = -1.0
      }
      i = i + 1
    }
    let mut exp = 0.0
    let mut edigits = 0
    while i < n && chars[i] >= '0' && chars[i] <= '9' {
      exp = exp * 10.0 + (chars[i].to_int() - 48).to_double()
      edigits = edigits + 1
      i = i + 1
    }
    if edigits == 0 {
      return None
    }
    value = value * @math.pow(10.0, esign * exp)
  }
  if i != n {
    return None
  }
  Some(sign * value)
}
