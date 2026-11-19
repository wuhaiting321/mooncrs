// 查看类子命令：describe / wkt / proj / list / search。
//
// 它们都不改数据，只把"这个 CRS 是什么"讲清楚；区别只在输出格式。
// 失败一律 `EXIT_FAILED`：坐标系写错是"换输入就能好"的错误，不是命令打错。

///|
/// `describe <CRS>`：打印坐标系详情。
fn cmd_describe(sink : Sink, args : Array[String]) -> Int32 {
  if args.length() < 1 {
    sink.line("用法: mooncrs describe <CRS>")
    sink.line("示例: mooncrs describe EPSG:27700")
    return EXIT_USAGE
  }
  let crs = @crs.parse(args[0]) catch {
    err => {
      report(sink, err)
      return EXIT_FAILED
    }
  }
  sink.block(@crs.describe(crs))
  EXIT_OK
}

///|
/// `wkt <CRS>`：转成 WKT2。
fn cmd_wkt(sink : Sink, args : Array[String]) -> Int32 {
  if args.length() < 1 {
    sink.line("用法: mooncrs wkt <CRS>")
    sink.line("示例: mooncrs wkt EPSG:27700")
    return EXIT_USAGE
  }
  let crs = @crs.parse(args[0]) catch {
    err => {
      report(sink, err)
      return EXIT_FAILED
    }
  }
  sink.block(@wkt.to_wkt2(crs))
  EXIT_OK
}

///|
/// `proj <CRS>`：转成 PROJ 串。
fn cmd_proj(sink : Sink, args : Array[String]) -> Int32 {
  if args.length() < 1 {
    sink.line("用法: mooncrs proj <CRS>")
    sink.line("示例: mooncrs proj EPSG:27700")
    return EXIT_USAGE
  }
  let crs = @crs.parse(args[0]) catch {
    err => {
      report(sink, err)
      return EXIT_FAILED
    }
  }
  sink.line(@projstr.to_proj(crs))
  EXIT_OK
}

///|
/// `list [起始] [结束]`：列出内置 EPSG 码。
fn cmd_list(sink : Sink, args : Array[String]) -> Int32 {
  let codes = @epsg.all_codes()
  let mut lo = 0.0
  let mut hi = 999999.0
  if args.length() >= 2 {
    match (parse_arg(args[0]), parse_arg(args[1])) {
      (Some(a), Some(b)) => {
        lo = a
        hi = b
      }
      _ =>
        return usage_error(sink, "list 的两个参数应当是 EPSG 码区间，例如 4000 4999")
    }
  }
  let mut i = 0
  let mut shown = 0
  while i < codes.length() {
    let code = codes[i]
    if code.to_double() >= lo && code.to_double() <= hi {
      sink.line("EPSG:" + code.to_string() + "  " + name_of(code))
      shown = shown + 1
    }
    i = i + 1
  }
  sink.line("共 " + shown.to_string() + " 个坐标系（内置共 " + codes.length().to_string() + " 个）")
  EXIT_OK
}

///|
/// 取坐标系名称；查询失败时返回占位符而不是中断整个列表。
fn name_of(code : Int32) -> String {
  try {
    @epsg.get(code).name()
  } catch {
    _ => "?"
  }
}

///|
/// `search <关键词>`：按名称搜索内置注册表。
fn cmd_search(sink : Sink, args : Array[String]) -> Int32 {
  if args.length() < 1 {
    sink.line("用法: mooncrs search <关键词>")
    sink.line("示例: mooncrs search 兰勃特")
    return EXIT_USAGE
  }
  let keyword = join_from(args, 0, " ")
  let hits = @epsg.search(keyword)
  for hit in hits {
    sink.line("EPSG:" + hit.0.to_string() + "  " + hit.1)
  }
  sink.line("命中 " + hits.length().to_string() + " 条")
  EXIT_OK
}

///|
/// 从某下标开始用分隔符连接。
fn join_from(items : Array[String], from : Int, sep : String) -> String {
  let sb = StringBuilder()
  let mut i = from
  while i < items.length() {
    if i > from {
      sb.write_string(sep)
    }
    sb.write_string(items[i])
    i = i + 1
  }
  sb.to_string()
}
