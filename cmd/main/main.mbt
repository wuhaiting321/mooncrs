// mooncrs CLI。
//
// 定位：一个**无依赖、单文件可跑**的坐标转换器。
// 传统做法是装 PROJ（连同 100 MB 的网格文件），或者装 GDAL；
// 这里只需要 `moon run cmd/main`，因为坐标系定义与投影算法都在库里，
// EPSG 注册表也是编进去的。
//
// 设计原则：输出全部走 stdout，便于管道；错误信息带"错误:"前缀；
// 任何一步失败都明确报错，不做"尽力而为"的静默降级。

///|
/// 入口。
fn main {
  let args = @env.args()
  dispatch(args)
}

///|
/// 子命令分派。
fn dispatch(args : Array[String]) -> Unit {
  let commands : Array[String] = [
    "transform",
    "describe",
    "wkt",
    "proj",
    "list",
    "search",
    "help",
    "version",
  ]
  let mut at = -1
  let mut i = 0
  while i < args.length() {
    for cmd in commands {
      if args[i] == cmd && at < 0 {
        at = i
      }
    }
    i = i + 1
  }
  if at < 0 {
    print_help()
    return
  }
  let cmd = args[at]
  let rest = tail(args, at + 1)
  match cmd {
    "transform" => run_transform(rest)
    "describe" => run_describe(rest)
    "wkt" => run_wkt(rest)
    "proj" => run_proj(rest)
    "list" => run_list(rest)
    "search" => run_search(rest)
    "version" => println("mooncrs " + version())
    _ => print_help()
  }
}

///|
/// 版本号。与 `moon.mod` 保持一致。
fn version() -> String {
  "0.1.0"
}

///|
/// `transform <源> <目标> <x> <y> [<x> <y> ...]`
///
/// 一次可以给多对坐标，便于批量处理；每行输出一对结果。
fn run_transform(args : Array[String]) -> Unit {
  if args.length() < 4 {
    println("用法: mooncrs transform <源CRS> <目标CRS> <x> <y> [<x> <y> ...]")
    println("示例: mooncrs transform EPSG:4326 EPSG:3857 116.3912 39.9075")
    return
  }
  let source = args[0]
  let target = args[1]
  let from = @crs.parse(source) catch {
    err => {
      report(err)
      return
    }
  }
  let to = @crs.parse(target) catch {
    err => {
      report(err)
      return
    }
  }
  let mut i = 2
  while i + 1 < args.length() {
    let x = parse_arg(args[i])
    let y = parse_arg(args[i + 1])
    match (x, y) {
      (Some(px), Some(py)) => {
        let result = @crs.transform(from, to, px, py) catch {
          err => {
            report(err)
            return
          }
        }
        println(show(result.0) + " " + show(result.1))
      }
      _ => {
        println("错误: 无法解析坐标 '" + args[i] + "' 或 '" + args[i + 1] + "'")
        return
      }
    }
    i = i + 2
  }
}

///|
/// `describe <CRS>`：打印坐标系详情。
fn run_describe(args : Array[String]) -> Unit {
  if args.length() < 1 {
    println("用法: mooncrs describe <CRS>")
    return
  }
  let crs = @crs.parse(args[0]) catch {
    err => {
      report(err)
      return
    }
  }
  println(@crs.describe(crs))
}

///|
/// `wkt <CRS>`：转成 WKT2。
fn run_wkt(args : Array[String]) -> Unit {
  if args.length() < 1 {
    println("用法: mooncrs wkt <CRS>")
    return
  }
  let crs = @crs.parse(args[0]) catch {
    err => {
      report(err)
      return
    }
  }
  println(@wkt.to_wkt2(crs))
}

///|
/// `proj <CRS>`：转成 PROJ 串。
fn run_proj(args : Array[String]) -> Unit {
  if args.length() < 1 {
    println("用法: mooncrs proj <CRS>")
    return
  }
  let crs = @crs.parse(args[0]) catch {
    err => {
      report(err)
      return
    }
  }
  println(@projstr.to_proj(crs))
}

///|
/// `list [起始] [结束]`：列出内置 EPSG 码。
fn run_list(args : Array[String]) -> Unit {
  let codes = @epsg.all_codes()
  let mut i = 0
  while i < codes.length() {
    let code = codes[i]
    let in_range = if args.length() >= 2 {
      let lo = parse_arg(args[0]).unwrap_or(0.0)
      let hi = parse_arg(args[1]).unwrap_or(999999.0)
      code.to_double() >= lo && code.to_double() <= hi
    } else {
      true
    }
    if in_range {
      println("EPSG:" + code.to_string() + "  " + name_of(code))
    }
    i = i + 1
  }
  println("共 " + codes.length().to_string() + " 个坐标系")
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
fn run_search(args : Array[String]) -> Unit {
  if args.length() < 1 {
    println("用法: mooncrs search <关键词>")
    return
  }
  let keyword = join_from(args, 0, " ")
  let hits = @epsg.search(keyword)
  for hit in hits {
    println("EPSG:" + hit.0.to_string() + "  " + hit.1)
  }
  println("命中 " + hits.length().to_string() + " 条")
}

///|
/// 帮助。
fn print_help() -> Unit {
  println("mooncrs " + version() + " — 坐标参考系转换引擎")
  println("")
  println("用法: mooncrs <命令> [参数...]")
  println("")
  println("命令:")
  println("  transform <源> <目标> <x> <y> [...]  坐标转换")
  println("  describe <CRS>                      查看坐标系定义")
  println("  wkt <CRS>                           输出 WKT2")
  println("  proj <CRS>                          输出 PROJ 串")
  println("  list [起始] [结束]                  列出内置 EPSG 码")
  println("  search <关键词>                     按名称搜索")
  println("  version                             版本号")
  println("")
  println("CRS 可以用四种写法之一：")
  println("  EPSG:4326                            注册表引用")
  println("  32650                                裸码")
  println("  +proj=utm +zone=50 +datum=WGS84      PROJ 串")
  println("  PROJCRS[\"...\",...]                 WKT2 / WKT1")
  println("")
  println("示例:")
  println("  mooncrs transform EPSG:4326 EPSG:3857 116.3912 39.9075")
  println("  mooncrs transform 4326 32650 116.3912 39.9075")
  println("  含空格的参数需要加引号，例如 WKT 或 PROJ 串。")
}

///|
/// 统一的错误输出。
fn report(err : @types.CrsError) -> Unit {
  println("错误: " + @types.CrsError::message(err))
}

///|
/// 数值输出：默认用最短可逆表示（`Double::to_string`），
/// 不做定点截断——截断会丢精度，而坐标转换最怕"看起来对"。
fn show(v : Double) -> String {
  if v == 0.0 {
    return "0"
  }
  v.to_string()
}

///|
/// 解析命令行里的数值。
fn parse_arg(raw : String) -> Double? {
  @projstr.parse_float(raw)
}

///|
/// 取数组的尾部。
fn tail(items : Array[String], from : Int) -> Array[String] {
  let out : Array[String] = []
  let mut i = from
  while i < items.length() {
    out.push(items[i])
    i = i + 1
  }
  out
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
