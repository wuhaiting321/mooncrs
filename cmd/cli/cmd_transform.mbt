// `transform` 子命令。
//
// 默认不打印解释，但只要 `--explain` 就打印：两个入口走的是同一个
// `transform_report`，报告的运算就是实际执行的那条，不会出现
// "解释里写用 A、结果却是用 B 算的"。

///|
/// `transform [--grid ID=PATH] [--explain] <源> <目标> <x> <y> [...]`
///
/// 一次可以给多对坐标，便于批量处理；每行输出一对结果。
fn cmd_transform(sink : Sink, argv : Array[String]) -> Int32 {
  let grids = @grid.GridSet::empty()
  let rest = match collect_grids(sink, argv, grids) {
    Some(r) => r
    None => return EXIT_FAILED
  }
  // `--explain` 与 `--grid` 互不干扰：先收网格，再把这个开关从剩余参数里挑出来。
  // 不放进 collect_grids，是因为那个函数管的是"要加载什么数据"，不是"要多说什么话"。
  let mut explain = false
  let args : Array[String] = []
  for a in rest {
    if a == "--explain" {
      explain = true
    } else {
      args.push(a)
    }
  }
  if args.length() < 4 {
    sink.line(
      "用法: mooncrs transform [--grid ID=PATH] [--explain] <源CRS> <目标CRS> <x> <y> [<x> <y> ...]",
    )
    sink.line("示例: mooncrs transform EPSG:4326 EPSG:3857 116.3912 39.9075")
    sink.line("示例: mooncrs transform --grid conus.gsb EPSG:4267 EPSG:4269 -96.0 32.0")
    sink.line("示例: mooncrs transform --explain EPSG:4277 EPSG:4258 1.7179 52.6576")
    return EXIT_USAGE
  }
  let from = @crs.parse(args[0]) catch {
    err => {
      report(sink, err)
      return EXIT_FAILED
    }
  }
  let to = @crs.parse(args[1]) catch {
    err => {
      report(sink, err)
      return EXIT_FAILED
    }
  }
  let mut i = 2
  while i + 1 < args.length() {
    let x = parse_arg(args[i])
    let y = parse_arg(args[i + 1])
    match (x, y) {
      (Some(px), Some(py)) => {
        // 默认也走 transform_report：多构造一个报告的开销可以忽略，但换来的是
        // "加不加 --explain 用的是同一条管道"，不会出现解释与实际结果对不上的情况。
        let result = @crs.transform_report(from, to, px, py, grids=grids) catch {
          err => {
            report(sink, err)
            return EXIT_FAILED
          }
        }
        sink.line(show(result.0) + " " + show(result.1))
        if explain {
          sink.block(result.2.to_text())
        }
      }
      _ => {
        sink.line("错误: 无法解析坐标 '" + args[i] + "' 或 '" + args[i + 1] + "'")
        sink.line("这两个参数应当是十进制数值，例如 `116.3912 39.9075`")
        return EXIT_USAGE
      }
    }
    i = i + 2
  }
  EXIT_OK
}
