// 统一错误类型。
//
// 为什么用 suberror 而不是 Result[_, String]：
// 调用方需要按错误类别分支处理（例如"这个投影还没实现"应当降级提示，
// 而"参数非法"应当直接报错），单靠字符串无法稳定区分。suberror 让调用方
// 可以 catch 到具体构造子，同时保持 `raise` 的轻量调用风格。

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
pub fn CrsError::message(self : CrsError) -> String {
  match self {
    Parse(m) => "解析失败: " + m
    Invalid(m) => "参数非法: " + m
    UnsupportedProjection(m) => "不支持的投影: " + m
    UnsupportedOperation(m) => "不支持的转换: " + m
    NotFound(m) => "未找到: " + m
    Domain(m) => "超出定义域: " + m
  }
}
