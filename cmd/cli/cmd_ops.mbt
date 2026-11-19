// `ops` 子命令：转换之前先看清有哪些路。
//
// 存在的理由：`--explain` 只说"用了哪条"，看不到"本来还能用哪条、为什么
// 没用上"。用户想判断"我这次的结果是不是能达到 0.1 m"，就必须知道更精确
// 的那条是否存在、缺的是数据还是实现——这正是"用户无法判断可用性"的正面回答。

///|
/// `ops --from <源> --to <目标> [--point <x> <y>] [--grid ID=PATH]`
///
/// 列出该基准对的全部候选运算，按精度排序，逐条标注适用性。
fn cmd_ops(sink : Sink, argv : Array[String]) -> Int32 {
  let grids = @grid.GridSet::empty()
  let rest = match collect_grids(sink, argv, grids) {
    Some(r) => r
    None => return EXIT_FAILED
  }
  let mut from_raw = ""
  let mut to_raw = ""
  let mut point : (Double, Double)? = None
  let mut i = 0
  while i < rest.length() {
    let a = rest[i]
    if a == "--from" || a == "-f" {
      if i + 1 >= rest.length() {
        return usage_error(sink, "--from 后面缺少源坐标系")
      }
      from_raw = rest[i + 1]
      i = i + 2
    } else if a == "--to" || a == "-t" {
      if i + 1 >= rest.length() {
        return usage_error(sink, "--to 后面缺少目标坐标系")
      }
      to_raw = rest[i + 1]
      i = i + 2
    } else if a == "--point" || a == "-p" {
      if i + 2 >= rest.length() {
        return usage_error(sink, "--point 后面需要两个数值（经度 纬度 或 x y）")
      }
      match (parse_arg(rest[i + 1]), parse_arg(rest[i + 2])) {
        (Some(lon), Some(lat)) => {
          point = Some((lon, lat))
          i = i + 3
        }
        _ =>
          return usage_error(
            sink,
            "--point 的两个参数应当是十进制数值，收到 '" +
            rest[i + 1] +
            "' 与 '" +
            rest[i + 2] +
            "'",
          )
      }
    } else {
      return usage_error(sink, "无法识别的参数 '" + a + "'")
    }
  }
  if from_raw == "" || to_raw == "" {
    return usage_error(sink, "必须同时给出 --from 与 --to")
  }
  let from = @crs.parse(from_raw) catch {
    err => {
      report(sink, err)
      return EXIT_FAILED
    }
  }
  let to = @crs.parse(to_raw) catch {
    err => {
      report(sink, err)
      return EXIT_FAILED
    }
  }
  let listed = candidates_or(from, to, grids, point) catch {
    err => {
      report(sink, err)
      return EXIT_FAILED
    }
  }
  if listed.length() == 0 {
    // 一条都没有时，说清缺什么，而不是给一个空列表让用户猜。
    let why = @operation.missing_message(from.datum(), to.datum()) catch {
      err => err.message()
    }
    sink.line("错误: " + why)
    return EXIT_FAILED
  }
  sink.line("源      " + from_raw + "  " + from.name())
  sink.line("目标    " + to_raw + "  " + to.name())
  match point {
    Some(p) => sink.line("点      " + show(p.0) + ", " + show(p.1))
    None => sink.line("点      未指定（只列范围，不判适用性）")
  }
  sink.line("")
  let mut usable = 0
  for c in listed {
    if c.ready && c.in_area != Some(false) {
      usable = usable + 1
    }
    sink.line(candidate_line(c))
  }
  sink.line("")
  sink.line(
    "共 " +
    listed.length().to_string() +
    " 条候选，其中 " +
    usable.to_string() +
    " 条在当前条件下可用",
  )
  sink.line("排序：标称精度升序 → 适用范围小者优先 → 标识字典序（全部同分时保证结果可复现）")
  EXIT_OK
}

///|
/// 有损的中间层：把"给点/没给点"的分支收在一处，让上面的 `catch` 只有一处。
fn candidates_or(
  from : @types.Crs,
  to : @types.Crs,
  grids : @grid.GridSet,
  point : (Double, Double)?,
) -> Array[@crs.Candidate] raise @types.CrsError {
  match point {
    Some(p) => @crs.list_candidates(from, to, grids=grids, point=p)
    None => @crs.list_candidates(from, to, grids=grids)
  }
}

///|
/// 一行候选。
///
/// 状态放在行尾，是因为前面的字段长度不齐（方法名有中文），把状态塞在
/// 中间会对不齐；行尾对齐至少能一眼扫到底。
fn candidate_line(c : @crs.Candidate) -> String {
  let op = c.operation
  let sb = StringBuilder()
  sb.write_string("  " + op.code + "  " + op.name)
  sb.write_string("  " + op.method_kind.label())
  sb.write_string("  精度 " + op.accuracy_text())
  if op.code == "LOCAL:INLINE_TOWGS84" {
    sb.write_string("  [定义文本自带，优先于注册表]")
  }
  if !c.ready {
    sb.write_string("  [缺数据] " + c.blocked)
  } else {
    match c.in_area {
      Some(true) => sb.write_string("  [适用于该点]")
      Some(false) => sb.write_string("  [超出范围] 适用范围 " + op.area.to_text())
      None => ()
    }
  }
  sb.to_string()
}

///|
fn usage_error(sink : Sink, why : String) -> Int32 {
  sink.line("错误: " + why)
  sink.line("用法: mooncrs ops --from <源CRS> --to <目标CRS> [--point <x> <y>] [--grid ID=PATH]")
  sink.line("示例: mooncrs ops --from EPSG:4277 --to EPSG:4258 --point 1.7179 52.6576")
  EXIT_USAGE
}
