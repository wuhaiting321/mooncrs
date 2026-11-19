// 统一错误类型。
//
// 为什么用 suberror 而不是 Result[_, String]：
// 调用方需要按错误类别分支处理（例如"这个投影还没实现"应当降级提示，
// 而"参数非法"应当直接报错），单靠字符串无法稳定区分。suberror 让调用方
// 可以 catch 到具体构造子，同时保持 `raise` 的轻量调用风格。
//
// 关于错误文案：本文件在拼接时统一做一次"可操作性检查"。理由很直接——
// 库里有一百多个 raise 点，靠人工逐条保证"每条消息都告诉用户下一步做什么"
// 是不现实的，漏一条就退化成"不支持"三个字。这里把它变成类型层面的约定：
// 消息里没有可操作信息时，自动补上该类别对应的下一步建议。具体分支的文案
// 仍然各写各的，这条只是兜底。

///|
/// mooncrs 的全部错误。
pub(all) suberror CrsError {
  /// 文本解析失败：WKT / PROJ 串语法错误。
  Parse(String)
  /// 结构正确但语义不合法：例如椭球长半轴为 0、纬度超出 [-90, 90]。
  Invalid(String)
  /// 投影方法尚未实现（按 EPSG 方法码或方法名区分）。
  UnsupportedProjection(String)
  /// 转换链中出现了无法处理的 CRS 组合。
  UnsupportedOperation(String)
  /// 查找失败：EPSG 码不在内置注册表里。
  NotFound(String)
  /// 数值定义域错误：例如反算时坐标落在投影有效范围外。
  Domain(String)
}

///|
/// 把错误转成人类可读的一句话，供 CLI 与日志使用。
///
/// 输出 = 类别前缀 + 具体描述（+ 必要时补的下一步建议）。
pub fn CrsError::message(self : CrsError) -> String {
  let prefix = match self {
    Parse(_) => "解析失败: "
    Invalid(_) => "参数非法: "
    UnsupportedProjection(_) => "不支持的投影: "
    UnsupportedOperation(_) => "不支持的转换: "
    NotFound(_) => "未找到: "
    Domain(_) => "超出定义域: "
  }
  let body = match self {
    Parse(m) | Invalid(m) | UnsupportedProjection(m) | UnsupportedOperation(m) | NotFound(m) | Domain(m) =>
      m
  }
  if actionable(body) {
    prefix + body
  } else if ends_with_stop(body) {
    prefix + body + self.hint_of()
  } else {
    prefix + body + "。" + self.hint_of()
  }
}

///|
/// 消息里是否已经含"下一步做什么"。
///
/// 判据是几个在中文技术文案里稳定表示"可操作"的词。不做语义分析——那需要
/// 模型；这里只要一个确定、可测试的规则。
fn actionable(body : String) -> Bool {
  let marks : Array[String] = [
    "请",
    "改用",
    "见 ",
    "docs/",
    "需要",
    "必需",
    "补上",
    "补充",
    "范围",
    "只支持",
    "必须",
    "检查",
    "写法",
    "收录",
  ]
  for m in marks {
    if body.contains(m) {
      return true
    }
  }
  false
}

///|
/// 各类错误的兜底建议。只在消息自身没有可操作信息时使用。
fn CrsError::hint_of(self : CrsError) -> String {
  match self {
    Parse(_) =>
      "请检查输入是否完整、格式是否为受支持的版本；坐标定义也可以直接用 EPSG 码引用（如 EPSG:4326），网格文件的要求见 docs/DATA.md"
    Invalid(_) => "请检查这个参数的定义；取值约定见 docs/ACCEPTANCE.md 与对应 EPSG 记录"
    UnsupportedProjection(_) => "可改用已实现的投影方法，清单见 README 的「支持的投影」一节"
    UnsupportedOperation(_) =>
      "需要在 operation 注册表补一条带范围与精度的运算，或改用带 +towgs84 的定义"
    NotFound(_) => "可改用 WKT2 或 PROJ 串直接给出定义，或用 `mooncrs search` 按名称查内置码"
    Domain(_) => "请把输入坐标换到该投影的有效范围内，或换用在该处有效的投影"
  }
}

///|
/// 是否已经以句号结尾。
fn ends_with_stop(body : String) -> Bool {
  if body.length() == 0 {
    return false
  }
  match body.get_char(body.length() - 1) {
    Some(c) => c == '。' || c == '；' || c == '!'
    None => false
  }
}

///|
/// 消息是否满足"可操作"的最低标准：长度过短、或没有下一步建议都算不合格。
///
/// 供测试与 CLI 自检使用。门槛取 20 个字符，是因为短于此的消息基本只够说
/// "错了"，不够说"错在哪、怎么办"。
pub fn CrsError::is_actionable(self : CrsError) -> Bool {
  let text = self.message()
  // 前缀（"解析失败: " 等）本身不含这些标记，所以直接对整条消息判定即可。
  text.length() > 20 && actionable(text)
}
