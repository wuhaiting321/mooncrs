// 运算选择：给定源/目标基准，找出候选运算并排序。
//
// 排序规则固定为三层，保证同一输入永远得到同一答案：
//   1. 标称精度升序（未声明的排最后，不许冒充高精度）
//   2. 同等精度下适用范围小的优先（专用运算优于全球运算）
//   3. 仍相同则按标识字典序（纯粹为了确定性）

///|
/// 列出源基准到目标基准的全部候选运算（已定向为 from → to）。
///
/// 反向运算在返回前派生（参数取反），所以注册表只需登记单向。
pub fn resolve(
  from : @types.Datum,
  to : @types.Datum,
) -> Array[CoordinateOperation] raise @types.CrsError {
  let out : Array[CoordinateOperation] = []
  if from.key == "UNKNOWN" || to.key == "UNKNOWN" {
    // 定义里根本没写基准。只有椭球完全相同时才敢假定重合，否则宁可报错：
    // 把 Clarke 1866 上的经纬度直接搬到 WGS84 上，误差是百米量级。
    if @types.same_ellipsoid(from.ellipsoid, to.ellipsoid) {
      out.push(assumed(from, to))
    }
    return out
  }
  if from.key == to.key {
    out.push(identity(from, to))
    return out
  }
  for op in all() {
    if op.source == from.key && op.target == to.key {
      out.push(op)
    }
    if op.source == to.key && op.target == from.key {
      out.push(op.inverse())
    }
  }
  sort_operations(out)
  out
}

///|
/// 只保留适用于该点的候选（按优先级排序）。
pub fn find_operations(
  from : @types.Datum,
  to : @types.Datum,
  lon : Double,
  lat : Double,
) -> Array[CoordinateOperation] raise @types.CrsError {
  let out : Array[CoordinateOperation] = []
  for op in resolve(from, to) {
    if op.area.contains(lon, lat) {
      out.push(op)
    }
  }
  out
}

///|
/// 没有可用运算时的可操作提示。
///
/// 只说"不支持"等于没做：用户需要知道改哪个基准、还是该补一条运算。
pub fn missing_message(
  from : @types.Datum,
  to : @types.Datum,
) -> String raise @types.CrsError {
  let partners = partners_of(from.key)
  let known = if partners.length() == 0 {
    "该基准在注册表中没有任何已登记的运算"
  } else {
    "该基准已登记的目标基准：" + join_strings(partners, " / ")
  }
  "没有 " +
  from.key +
  " → " +
  to.key +
  " 的坐标运算。" +
  known +
  "。可选做法：改用 WKT/PROJ 直接给出 +towgs84 参数，或在 operation 注册表补充一条带范围与精度的运算"
}

///|
/// 该点落在范围外时，说明最近的可用范围。
pub fn outside_message(
  op : CoordinateOperation,
  lon : Double,
  lat : Double,
) -> String {
  "坐标 (" +
  lon.to_string() +
  ", " +
  lat.to_string() +
  ") 不在运算 " +
  op.code +
  " 的适用范围内（" +
  op.area.to_text() +
  "）"
}

///|
/// 同一基准的恒等运算。
fn identity(from : @types.Datum, to : @types.Datum) -> CoordinateOperation {
  {
    code: "LOCAL:IDENTITY",
    name: from.key + " ↔ " + to.key + "（同一基准）",
    method_kind: Identity,
    params: OperationParams::NoParams,
    source: from.key,
    target: to.key,
    area: BoundingBox::world(),
    accuracy_m: Some(0.0),
    authority: "definition",
    note: "同一基准，只有投影或单位差异，不做基准变换",
    reversed: false,
  }
}

///|
/// 假定重合。只允许在椭球完全相同时产生，且必须带警告。
fn assumed(from : @types.Datum, to : @types.Datum) -> CoordinateOperation {
  {
    code: "LOCAL:ASSUMED_COINCIDENT",
    name: from.name + " → " + to.name + "（假定重合）",
    method_kind: Assumed,
    params: OperationParams::NoParams,
    source: from.key,
    target: to.key,
    area: BoundingBox::world(),
    accuracy_m: None,
    authority: "definition text",
    note: "定义中未声明基准，仅因两侧椭球完全一致而假定重合；误差未知，不可用于成果提交",
    reversed: false,
  }
}

///|
/// 三层排序。
fn sort_operations(ops : Array[CoordinateOperation]) -> Unit {
  let n = ops.length()
  let mut i = 1
  while i < n {
    let key = ops[i]
    let mut j = i
    while j > 0 && before(key, ops[j - 1]) {
      ops[j] = ops[j - 1]
      j = j - 1
    }
    ops[j] = key
    i = i + 1
  }
}

///|
/// `a` 是否应排在 `b` 之前。
fn before(a : CoordinateOperation, b : CoordinateOperation) -> Bool {
  let ra = a.accuracy_rank()
  let rb = b.accuracy_rank()
  if ra != rb {
    return ra < rb
  }
  let ea = a.area.extent()
  let eb = b.area.extent()
  if ea != eb {
    return ea < eb
  }
  a.code < b.code
}

///|
/// 拼接字符串数组。
fn join_strings(items : Array[String], sep : String) -> String {
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
