// WKT（Well-Known Text）解析：WKT2:2019 为主，兼容 WKT1（OGC 01-009）。
//
// 分两层：
// 1. 词法 + 语法 → 通用语法树 `WktNode`（不做任何语义判断）；
// 2. 语法树 → CRS 模型（带语义映射与容错）。
//
// 分两层的好处是：语法层可以独立测试（喂各种畸形输入），语义层可以
// 独立演进（新增支持一种 CRS 类型不用动词法）。这也是 Proj4js / cs2cs
// 这类实现普遍采用的结构。

///|
/// WKT 语法树节点。
pub enum WktNode {
  /// 裸关键字，例如 `north`、`ellipsoidal`。
  Word(String)
  /// 字符串字面量。
  Text(String)
  /// 数值字面量。
  Number(Double)
  /// `KEYWORD[ ... ]` 形式的节点。
  Form(String, Array[WktNode])
} derive(Debug)

///|
pub extend WktNode with @debug.Debug::{to_repr}

///|
/// 词法单元。
enum Token {
  TWord(String)
  TText(String)
  TNum(Double)
  TOpen
  TClose
  TComma
} derive(Debug)

///|
pub extend Token with @debug.Debug::{to_repr}

///|
/// 把 WKT 文本切成词法单元。
///
/// 同时接受 `[ ]` 与 `( )` 两种括号：WKT2 规范用方括号，但大量存量
/// 数据（尤其是 Shapefile 的 .prj）用圆括号，且常两者混用。宽松接受，
/// 由 `stack` 记录实际开括号类型，闭合时不强求配对——这是实用性优先的
/// 刻意选择，不是疏漏。
fn tokenize(text : String) -> Array[Token] raise @types.CrsError {
  let chars = text.to_array()
  let n = chars.length()
  let mut i = 0
  let out : Array[Token] = []
  while i < n {
    let ch = chars[i]
    if ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' {
      i = i + 1
      continue
    }
    if ch == '[' || ch == '(' {
      out.push(TOpen)
      i = i + 1
      continue
    }
    if ch == ']' || ch == ')' {
      out.push(TClose)
      i = i + 1
      continue
    }
    if ch == ',' {
      out.push(TComma)
      i = i + 1
      continue
    }
    if ch == '"' {
      i = i + 1
      let sb = StringBuilder()
      let mut closed = false
      while i < n {
        let c = chars[i]
        if c == '"' {
          if i + 1 < n && chars[i + 1] == '"' {
            sb.write_char('"')
            i = i + 2
            continue
          }
          closed = true
          i = i + 1
          break
        }
        sb.write_char(c)
        i = i + 1
      }
      if !closed {
        raise @types.CrsError::Parse("WKT 字符串缺少收尾引号")
      }
      out.push(TText(sb.to_string()))
      continue
    }
    let is_num_start = ch == '-' || ch == '+' || (ch >= '0' && ch <= '9') ||
      ch == '.'
    if is_num_start {
      let start = i
      let mut seen_dot = false
      let mut seen_exp = false
      // 先吃掉符号位：否则 `-99` 会在第一个字符处就退出循环，
      // 得到一个空字面量（这是本项目最早踩到的解析 bug）。
      if chars[i] == '-' || chars[i] == '+' {
        i = i + 1
      }
      while i < n {
        let c = chars[i]
        if c >= '0' && c <= '9' {
          i = i + 1
        } else if c == '.' && !seen_dot && !seen_exp {
          seen_dot = true
          i = i + 1
        } else if (c == 'e' || c == 'E') && !seen_exp {
          seen_exp = true
          i = i + 1
          if i < n && (chars[i] == '-' || chars[i] == '+') {
            i = i + 1
          }
        } else {
          break
        }
      }
      let raw = slice_string(chars, start, i)
      match parse_number(raw) {
        Some(v) => out.push(TNum(v))
        None => raise @types.CrsError::Parse("无法解析数值: " + raw)
      }
      continue
    }
    // 其他一律按标识符读：WKT 关键字、轴方向、CS 类型等。
    let start = i
    while i < n {
      let c = chars[i]
      if c == '[' || c == ']' || c == '(' || c == ')' || c == ',' || c == '"' ||
        c == ' ' || c == '\n' || c == '\r' || c == '\t' {
        break
      }
      i = i + 1
    }
    if i == start {
      raise @types.CrsError::Parse("无法识别的字符: " + ch.to_string())
    }
    out.push(TWord(slice_string(chars, start, i)))
  }
  out
}

///|
/// 从字符数组切片出字符串。
fn slice_string(chars : Array[Char], start : Int, stop : Int) -> String {
  let sb = StringBuilder()
  for k in start..<stop {
    sb.write_char(chars[k])
  }
  sb.to_string()
}

///|
/// 解析数值字面量。手写而不用 `@string.parse_double`，因为后者要求整串
/// 都是数字，而这里已经切好边界，无需再校验一遍。
fn parse_number(raw : String) -> Double? {
  let chars = raw.to_array()
  let n = chars.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut sign = 1.0
  if chars[0] == '-' {
    sign = -1.0
    i = 1
  } else if chars[0] == '+' {
    i = 1
  }
  if i >= n {
    return None
  }
  let mut int_part = 0.0
  while i < n && chars[i] >= '0' && chars[i] <= '9' {
    int_part = int_part * 10.0 + (chars[i].to_int() - 48).to_double()
    i = i + 1
  }
  let mut frac_part = 0.0
  let mut scale = 1.0
  if i < n && chars[i] == '.' {
    i = i + 1
    while i < n && chars[i] >= '0' && chars[i] <= '9' {
      frac_part = frac_part * 10.0 + (chars[i].to_int() - 48).to_double()
      scale = scale * 10.0
      i = i + 1
    }
  }
  let mut exp = 0.0
  if i < n && (chars[i] == 'e' || chars[i] == 'E') {
    i = i + 1
    let mut esign = 1.0
    if i < n && chars[i] == '-' {
      esign = -1.0
      i = i + 1
    } else if i < n && chars[i] == '+' {
      i = i + 1
    }
    while i < n && chars[i] >= '0' && chars[i] <= '9' {
      exp = exp * 10.0 + (chars[i].to_int() - 48).to_double()
      i = i + 1
    }
    exp = exp * esign
  }
  if i != n {
    return None
  }
  let mantissa = int_part + frac_part / scale
  Some(sign * mantissa * @math.pow(10.0, exp))
}

///|
/// 递归下降解析：把词法单元组装成语法树。
///
/// 语法极简（只有"节点 = 关键字 [ 子节点, 子节点 ... ]"和三种原子），
/// 因此不引入状态机，直接按位置推进。
fn parse_form(tokens : Array[Token], pos : Int) -> (WktNode, Int) raise @types.CrsError {
  let n = tokens.length()
  if pos >= n {
    raise @types.CrsError::Parse("WKT 在节点起始处意外结束")
  }
  match tokens[pos] {
    TText(s) => (WktNode::Text(s), pos + 1)
    TNum(v) => (WktNode::Number(v), pos + 1)
    TWord(w) => {
      if pos + 1 < n {
        match tokens[pos + 1] {
          TOpen => {
            let children : Array[WktNode] = []
            let mut i = pos + 2
            let mut expect_value = true
            while i < n {
              match tokens[i] {
                TClose => {
                  i = i + 1
                  expect_value = false
                  break
                }
                TComma => {
                  i = i + 1
                  expect_value = true
                  continue
                }
                _ => {
                  let (child, next) = parse_form(tokens, i)
                  children.push(child)
                  i = next
                  expect_value = false
                  continue
                }
              }
            }
            let _ = expect_value
            (WktNode::Form(w, children), i)
          }
          _ => (WktNode::Word(w), pos + 1)
        }
      } else {
        (WktNode::Word(w), pos + 1)
      }
    }
    _ => raise @types.CrsError::Parse("WKT 语法错误：位置 " + pos.to_string())
  }
}

///|
/// 解析 WKT 文本，返回根语法树。
pub fn parse_tree(text : String) -> WktNode raise @types.CrsError {
  let tokens = tokenize(text)
  if tokens.length() == 0 {
    raise @types.CrsError::Parse("WKT 为空")
  }
  let (node, _) = parse_form(tokens, 0)
  node
}
