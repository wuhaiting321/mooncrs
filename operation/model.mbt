// 坐标运算的数据模型。
//
// 这一层只回答"有哪些运算、它们各自在什么范围成立、精度多少"，
// 不做任何数学。数学在 crs 包（它依赖本包，本包不反向依赖它）。

///|
/// 经纬度矩形（适用范围）。
///
/// 用矩形而不是多边形：EPSG 的 area of use 本身就记作外接矩形，
/// 多边形的精度是假象——真实适用范围本来就是"大致这一片"。
pub struct BoundingBox {
  south : Double
  west : Double
  north : Double
  east : Double
}

///|
/// 构造范围。越界或退化（南≥北、西≥东）直接报错，不做"修正"。
pub fn BoundingBox::new(
  south : Double,
  west : Double,
  north : Double,
  east : Double,
) -> BoundingBox raise @types.CrsError {
  if south < -90.0 || north > 90.0 {
    raise @types.CrsError::Invalid(
      "适用范围纬度越界: " + south.to_string() + " .. " + north.to_string(),
    )
  }
  if west < -180.0 || east > 180.0 {
    raise @types.CrsError::Invalid(
      "适用范围经度越界: " + west.to_string() + " .. " + east.to_string(),
    )
  }
  if south >= north {
    raise @types.CrsError::Invalid("适用范围南界不小于北界")
  }
  if west >= east {
    raise @types.CrsError::Invalid("适用范围西界不小于东界")
  }
  { south, west, north, east }
}

///|
/// 全球范围。
pub fn BoundingBox::world() -> BoundingBox {
  { south: -90.0, west: -180.0, north: 90.0, east: 180.0 }
}

///|
/// 点是否落在范围内（含边界）。
pub fn BoundingBox::contains(self : BoundingBox, lon : Double, lat : Double) -> Bool {
  lat >= self.south && lat <= self.north && lon >= self.west && lon <= self.east
}

///|
/// 面积（平方度），只用于"同样精度下优先选范围更小的"这类排序。
pub fn BoundingBox::extent(self : BoundingBox) -> Double {
  (self.north - self.south) * (self.east - self.west)
}

///|
/// 是否覆盖全球。
pub fn BoundingBox::is_world(self : BoundingBox) -> Bool {
  self.south <= -89.999 && self.north >= 89.999 && self.extent() > 64000.0
}

///|
/// 可读范围文本。
pub fn BoundingBox::to_text(self : BoundingBox) -> String {
  "[" +
  fmt_deg(self.south) +
  ", " +
  fmt_deg(self.west) +
  "] .. [" +
  fmt_deg(self.north) +
  ", " +
  fmt_deg(self.east) +
  "]"
}

///|
/// 坐标运算的方法族。
///
/// 方法决定"需要什么数据"和"精度上限"，是判断结果可用性的第一层依据。
pub(all) enum OperationMethod {
  /// 两个基准视为重合，不做任何计算。
  Identity
  /// 假定重合（定义里没写基准，且椭球完全相同）。已知不可靠，必须警告。
  Assumed
  /// EPSG 9603：三参数地心平移。
  GeocentricTranslation3
  /// EPSG 9606：七参数，位置向量约定。
  PositionVector7
  /// EPSG 9607：七参数，坐标框架约定。
  CoordinateFrame7
  /// EPSG 9604 / 9605：Molodensky 近似。
  Molodensky
  /// EPSG 9615：NTv2 网格改正（需 `.gsb` 文件）。
  Ntv2Grid
  /// EPSG 9613 / 9614：NADCON 网格改正（需 `.las` / `.los` 文件）。
  NadconGrid
  /// 无参数兜底：只为量级参考存在。
  Ballpark
}

///|
/// 方法是否需要外部网格文件。
pub fn OperationMethod::needs_grid(self : OperationMethod) -> Bool {
  match self {
    Ntv2Grid => true
    NadconGrid => true
    _ => false
  }
}

///|
/// 方法对应的 EPSG 方法码（无对应码时为空串）。
pub fn OperationMethod::epsg_code(self : OperationMethod) -> String {
  match self {
    Identity => "9603"
    Assumed => ""
    GeocentricTranslation3 => "9603"
    PositionVector7 => "9606"
    CoordinateFrame7 => "9607"
    Molodensky => "9604"
    Ntv2Grid => "9615"
    NadconGrid => "9613"
    Ballpark => ""
  }
}

///|
/// 方法名。
pub fn OperationMethod::label(self : OperationMethod) -> String {
  match self {
    Identity => "恒等（基准重合）"
    Assumed => "假定重合（未声明基准）"
    GeocentricTranslation3 => "三参数地心平移"
    PositionVector7 => "七参数（位置向量）"
    CoordinateFrame7 => "七参数（坐标框架）"
    Molodensky => "Molodensky 近似"
    Ntv2Grid => "NTv2 网格改正"
    NadconGrid => "NADCON 网格改正"
    Ballpark => "无参数兜底"
  }
}

///|
/// 运算参数。
pub(all) enum OperationParams {
  /// Helmert 参数（三参数为旋转/尺度全 0 的特例）。
  Helmert(@types.Helmert)
  /// 网格标识（文件名或逻辑名），运行时由调用方提供数据。
  Grid(String)
  /// 无参数。
  NoParams
}

///|
/// 一条坐标运算。
///
/// 这是本库对外承诺精度的唯一载体：没有 `accuracy_m` 的运算必须在报告里
/// 显式说明"精度未声明"，不许当成高精度用。
pub struct CoordinateOperation {
  /// 运算标识，`EPSG:7709` 或 `LOCAL:OSGB36_ETRS89_7P`。
  code : String
  name : String
  method_kind : OperationMethod
  params : OperationParams
  /// 源基准的规范标识。
  source : String
  /// 目标基准的规范标识。
  target : String
  area : BoundingBox
  /// 标称精度（米）。`None` 表示来源未声明，不是"零误差"。
  accuracy_m : Double?
  /// 参数出处：`EPSG` / `PROJ datum table` / `definition text`。
  authority : String
  /// 补充说明，给读报告的人看。
  note : String
  /// 是否为反向使用（目标 → 源）。
  ///
  /// 反向不靠"参数取反"实现：尺度取反是 1+s 而不是 1/s，会留下约毫米级
  /// 残差。这里保留原始参数、只翻一个标志，执行时走严格反解。
  reversed : Bool
}

///|
/// 构造运算。范围非法直接报错，不留"坏记录"进注册表。
pub fn CoordinateOperation::new(
  code~ : String,
  name~ : String,
  method_kind~ : OperationMethod,
  params~ : OperationParams,
  source~ : String,
  target~ : String,
  area~ : BoundingBox,
  accuracy_m~ : Double?,
  authority~ : String,
  note~ : String = "",
  reversed~ : Bool = false,
) -> CoordinateOperation raise @types.CrsError {
  if code.length() == 0 {
    raise @types.CrsError::Invalid("运算缺少标识")
  }
  match accuracy_m {
    Some(a) =>
      if a < 0.0 {
        raise @types.CrsError::Invalid("精度不能为负: " + code)
      }
    None => ()
  }
  {
    code,
    name,
    method_kind,
    params,
    source,
    target,
    area,
    accuracy_m,
    authority,
    note,
    reversed,
  }
}

///|
/// 是否需要外部网格数据。
pub fn CoordinateOperation::needs_grid(self : CoordinateOperation) -> Bool {
  self.method_kind.needs_grid()
}

///|
/// 在给定网格可用性的前提下，这条运算能否真正执行。
pub fn CoordinateOperation::is_executable(
  self : CoordinateOperation,
  grid_available : Bool,
) -> Bool {
  if self.needs_grid() {
    grid_available
  } else {
    true
  }
}

///|
/// 是否是"假定重合"（定义里没写基准）。这类运算必须带警告。
pub fn CoordinateOperation::is_assumed(self : CoordinateOperation) -> Bool {
  match self.method_kind {
    Assumed => true
    _ => false
  }
}

///|
/// 精度文本。`None` 显示"未声明"而不是"0"。
pub fn CoordinateOperation::accuracy_text(self : CoordinateOperation) -> String {
  match self.accuracy_m {
    Some(a) =>
      if a < 0.001 {
        "优于 1 mm"
      } else if a < 1.0 {
        a.to_string() + " m"
      } else {
        a.to_string() + " m"
      }
    None => "未声明"
  }
}

///|
/// 排序用的精度键：未声明的排在最后，而不是当成 0（当成 0 会被优先选中，
/// 那正好是"最不可信的最优先"）。
pub fn CoordinateOperation::accuracy_rank(self : CoordinateOperation) -> Double {
  match self.accuracy_m {
    Some(a) => a
    None => 1.0e9
  }
}

///|
/// 反向运算：交换源/目标，并标记 `reversed`。
///
/// 参数保持原样（它们属于正向），执行时由 `apply_operation` 选择严格反解。
/// 早先的写法是把参数逐个取反再当正向算：尺度会变成 `1+s` 而不是 `1/s`，
/// 在 20 ppm 的参数集上留下约 6 mm 的往返残差——足以让"毫米级闭环"的
/// 测试变成自欺。
pub fn CoordinateOperation::inverse(self : CoordinateOperation) -> CoordinateOperation {
  {
    code: self.code + "/inverse",
    name: self.name + "（反向）",
    method_kind: self.method_kind,
    params: self.params,
    source: self.target,
    target: self.source,
    area: self.area,
    accuracy_m: self.accuracy_m,
    authority: self.authority,
    note: self.note,
    reversed: !self.reversed,
  }
}

///|
/// 一行摘要。
pub fn CoordinateOperation::to_text(self : CoordinateOperation) -> String {
  self.code +
  "  " +
  self.name +
  "  [" +
  self.method_kind.label() +
  "]  精度 " +
  self.accuracy_text() +
  "  范围 " +
  self.area.to_text()
}

///|
/// 一次转换的完整报告。
///
/// 这是回应"用户如何判断结果是否可用"的接口：不看它，用户只知道坐标；
/// 看了它，用户知道用了哪条运算、误差上限、有没有降级。
pub struct TransformationReport {
  operation : CoordinateOperation
  /// 影响可用性判断的警告。空数组表示"没有需要提醒的事"。
  warnings : Array[String]
  /// 实际执行的步骤，按顺序。
  steps : Array[String]
  /// 因缺数据或超范围而被跳过的更优运算说明。
  skipped : Array[String]
}

///|
/// 构造报告。
pub fn TransformationReport::new(
  operation~ : CoordinateOperation,
  warnings~ : Array[String] = [],
  steps~ : Array[String] = [],
  skipped~ : Array[String] = [],
) -> TransformationReport {
  { operation, warnings, steps, skipped }
}

///|
/// 报告是否"完全无保留"（无警告、无跳过、精度已声明）。
pub fn TransformationReport::is_clean(self : TransformationReport) -> Bool {
  self.warnings.length() == 0 &&
  self.skipped.length() == 0 &&
  self.operation.accuracy_m is Some(_)
}

///|
/// 多行报告文本。
pub fn TransformationReport::to_text(self : TransformationReport) -> String {
  let sb = StringBuilder()
  sb.write_string("运算    " + self.operation.code + "  " + self.operation.name + "\n")
  sb.write_string("方法    " + self.operation.method_kind.label() + "\n")
  sb.write_string("精度    " + self.operation.accuracy_text() + "\n")
  sb.write_string("范围    " + self.operation.area.to_text() + "\n")
  sb.write_string("出处    " + self.operation.authority + "\n")
  if self.operation.note.length() > 0 {
    sb.write_string("说明    " + self.operation.note + "\n")
  }
  if self.steps.length() > 0 {
    sb.write_string("步骤\n")
    for step in self.steps {
      sb.write_string("        · " + step + "\n")
    }
  }
  if self.skipped.length() > 0 {
    sb.write_string("已跳过\n")
    for s in self.skipped {
      sb.write_string("        · " + s + "\n")
    }
  }
  if self.warnings.length() > 0 {
    sb.write_string("警告\n")
    for w in self.warnings {
      sb.write_string("        ! " + w + "\n")
    }
  }
  sb.to_string()
}

///|
/// 度数格式化：最多两位小数，去掉多余的 `.0`。
fn fmt_deg(v : Double) -> String {
  let scaled = (v * 100.0).round() / 100.0
  let raw = scaled.to_string()
  if raw.length() > 2 && raw.contains(".") {
    raw
  } else {
    raw
  }
}
