// 候选运算清单。
//
// 这一层回答的问题是"这次转换**本来**可以用哪些运算，各自为什么能用/不能用"，
// 而不是"最后用了哪一条"。`transform --explain` 只说最后那条，用户看不到
// 被他错过的高精度方案；`ops` 子命令把整张清单摊开，包括"因为缺 .gsb 被跳过"
// 的那条。两处共用本文件，避免出现"命令行说有三条、转换却走了第四条"。

///|
/// 候选运算的可执行状态。
pub(all) struct Candidate {
  operation : @operation.CoordinateOperation
  /// 数据是否就绪。非网格运算恒为 `true`；网格运算要求 `.gsb` 已加载。
  ready : Bool
  /// `ready == false` 时说明缺什么、去哪补；`ready == true` 时为空串。
  blocked : String
  /// 点是否落在适用范围内。没给点时是 `None`——"没问"不等于"不适用"。
  in_area : Bool?
}

///|
/// 列出全部候选，按精度排序（未声明精度的排最后）。
///
/// `point` 给了就顺带标出该点是否落在范围内。范围判断放在这里而不是调用方，
/// 是因为同一个 `contains` 判定在 `pick` 里已经用过一次，两处各写一遍迟早
/// 会因为边界开闭不一致而互相打脸。
pub fn list_candidates(
  from : @types.Crs,
  to : @types.Crs,
  grids? : @grid.GridSet,
  point? : (Double, Double),
) -> Array[Candidate] raise @types.CrsError {
  let gs = match grids {
    Some(g) => g
    None => @grid.GridSet::empty()
  }
  let src = from.datum()
  let dst = to.datum()
  let ops : Array[@operation.CoordinateOperation] = []
  // 定义文本自带的 towgs84 也算候选。它不在注册表里，但对用户来说它就是
  // "我这份定义能用的运算"，不列出来等于藏着。
  match inline_operation(from, dst) {
    Some(op) => ops.push(op)
    None => ()
  }
  for op in @operation.resolve(src, dst) {
    ops.push(op)
  }
  @operation.sort_operations(ops)
  let out : Array[Candidate] = []
  for op in ops {
    let (ready, blocked) = availability(op, gs)
    out.push({ operation: op, ready, blocked, in_area: mark(op, point) })
  }
  out
}

///|
/// 定义文本自带的 `towgs84` 能否作为本次转换的候选。
///
/// 只在"目标是 WGS84 家族"时成立：`TOWGS84` 的语义单向，它描述的是
/// "本基准 → WGS84"，反着用或转去别的基准都没有依据。
pub fn inline_operation(
  from : @types.Crs,
  dst : @types.Datum,
) -> @operation.CoordinateOperation? raise @types.CrsError {
  match from.inline_towgs84() {
    Some(h) => {
      if !wgs84_family(dst.key) {
        return None
      }
      let method_kind = if h.is_translation_only() {
        @operation.GeocentricTranslation3
      } else {
        @operation.PositionVector7
      }
      Some(
        @operation.CoordinateOperation::new(
          code="LOCAL:INLINE_TOWGS84",
          name="定义文本自带的 towgs84",
          method_kind~,
          params=@operation.OperationParams::Helmert(h),
          source=from.datum().key,
          target=dst.key,
          area=@operation.BoundingBox::world(),
          accuracy_m=None,
          authority="definition text",
          note="参数来自 WKT 的 TOWGS84 或 PROJ 的 +towgs84，无适用范围、无精度声明",
        ),
      )
    }
    None => None
  }
}

///|
/// 这条运算在当前数据下能不能真的跑起来。
///
/// 返回的说明只讲"缺什么、怎么补"，不重复运算标识与精度——那些由调用方
/// 拼在前面（`build_plan` 拼成 skipped 行，`ops` 拼成状态列）。
fn availability(
  op : @operation.CoordinateOperation,
  gs : @grid.GridSet,
) -> (Bool, String) {
  if !op.needs_grid() {
    return (true, "")
  }
  // 网格类运算分三种情况：数据已加载可执行、数据缺失、格式本版不支持。
  // 三种都要能被用户看懂，尤其是第三种——把"没实现"说成"缺数据"是骗人。
  match op.method_kind {
    NadconGrid =>
      (false, "使用 NADCON 的 .las/.los 格式，本版只实现 NTv2（.gsb）解析，已跳过")
    _ =>
      match gs.get(grid_id_of(op)) {
        Some(_) => (true, "")
        None =>
          (
            false,
            "更精确，但需要网格文件 " +
            grid_id_of(op) +
            ".gsb；当前未加载，用 --grid 指定文件，索取方式见 docs/DATA.md",
          )
      }
  }
}

///|
/// 该点是否在运算范围内。
fn mark(
  op : @operation.CoordinateOperation,
  point : (Double, Double)?,
) -> Bool? {
  match point {
    Some(p) => Some(op.area.contains(p.0, p.1))
    None => None
  }
}

///|
/// 把"定义文本自带"的那条挪到最前面。
///
/// 排序规则（精度优先）是给注册表用的：同一对基准的多条官方运算里，谁更准
/// 谁优先。但定义文本里的参数是**用户自己写下来的**，它盖过注册表是 PROJ
/// 的既定语义，也是用户的合理预期——他写了 `+towgs84` 就是想用它。
/// 这条覆盖只在选择阶段生效，`ops` 列表仍按精度展示，并单独标注，不藏。
pub fn prefer_inline(
  candidates : Array[Candidate],
) -> Array[Candidate] {
  let out : Array[Candidate] = []
  let rest : Array[Candidate] = []
  for c in candidates {
    if c.operation.code == "LOCAL:INLINE_TOWGS84" {
      out.push(c)
    } else {
      rest.push(c)
    }
  }
  for c in rest {
    out.push(c)
  }
  out
}
