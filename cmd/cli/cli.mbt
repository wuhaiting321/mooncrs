// CLI 的骨架：输出缓冲、退出码、子命令分派。
//
// 为什么命令实现不直接 `println`：输出要能被测试逐字节比对（"同一输入两次
// 运行是否完全相同"），退出码要能被断言（"参数错和可恢复错误是不是不同"),
// 这两件事都要求"运行的产物"是一个值，而不是散落在若干次打印调用里。
// 所以命令只往 `Sink` 里写，`main` 负责最后一次性吐出去。
//
// 顺带解决了一个老问题：`--grid` 的加载提示原本走 stderr、错误走 stdout，
// 管道里混着看会很乱；现在两条流分开收集，各自输出。

///|
/// 一次调用的退出码。
///
/// 分三档而不是 0/1，是因为调用方要区分"我命令打错了"和"数据/参数本身不行"：
/// 前者重打命令就好，后者要换坐标系或补网格文件，脚本里的处理方式不同。
pub const EXIT_OK : Int32 = 0

///|
/// 参数错误：命令名、选项名、参数个数不对。重写命令即可。
pub const EXIT_USAGE : Int32 = 1

///|
/// 可恢复错误：CRS 解析失败、找不到运算、点超出范围、文件读不了。
/// 换个输入就能成功，所以和"命令打错了"分开。
pub const EXIT_FAILED : Int32 = 2

///|
/// 输出缓冲。
///
/// 按行收集而不是拼一个大字符串：报告文本本身带换行，拼接时很容易多一个
/// 或少一个，而"输出逐字节一致"是硬要求，不能靠手工数换行符。
pub struct Sink {
  out : Array[String]
  err : Array[String]
}

///|
pub fn Sink::new() -> Sink {
  { out: [], err: [] }
}

///|
/// 写一行到 stdout。
pub fn Sink::line(self : Sink, text : String) -> Unit {
  self.out.push(text)
}

///|
/// 写一组已经分好行的文本（例如 `TransformationReport::to_text()`）。
pub fn Sink::block(self : Sink, text : String) -> Unit {
  if text.length() == 0 {
    return
  }
  let line = StringBuilder()
  let mut i = 0
  while i < text.length() {
    match text.get_char(i) {
      Some(c) =>
        if c == '\n' {
          self.out.push(line.to_string())
          line.reset()
        } else {
          line.write_char(c)
        }
      None => ()
    }
    i = i + 1
  }
  // 末尾没有换行时，最后一行同样要收进去。
  let last = line.to_string()
  if last.length() > 0 {
    self.out.push(last)
  }
}

///|
/// 写一行到 stderr。只用于"过程提示"（如已加载哪个网格），不用于结果。
pub fn Sink::note(self : Sink, text : String) -> Unit {
  self.err.push(text)
}

///|
pub fn Sink::out_text(self : Sink) -> String {
  join_lines(self.out)
}

///|
pub fn Sink::err_text(self : Sink) -> String {
  join_lines(self.err)
}

///|
/// 一次调用的完整产物。
pub struct CliOutput {
  out : String
  err : String
  code : Int32
}

///|
/// 分派。测试直接调它，不经过进程。
///
/// 参数约定：`args` 是**程序名之后**的全部参数，也就是用户在终端里敲的那些。
/// 把程序名剥在外面（`main` 里做），是因为"程序叫什么"和"要干什么"是两件事：
/// 混在一起就得靠"猜哪个词像命令"来分派，猜错一次就会把 `describe check`
/// 当成 `check` 子命令。
pub fn dispatch(args : Array[String]) -> CliOutput {
  let sink = Sink::new()
  let code = route(sink, args)
  { out: sink.out_text(), err: sink.err_text(), code }
}

///|
/// 子命令名。
///
/// 顺序即帮助里的顺序。`ops` 排在 `transform` 后面，因为它的用途是
/// "转换之前先看看有哪些路可走"。
fn command_names() -> Array[String] {
  [
    "transform",
    "ops",
    "grid",
    "describe",
    "wkt",
    "proj",
    "list",
    "search",
    "help",
    "version",
  ]
}

///|
fn route(sink : Sink, args : Array[String]) -> Int32 {
  if args.length() == 0 {
    // 什么都没给是有意看帮助，不算错误。
    print_help(sink)
    return EXIT_OK
  }
  let cmd = args[0]
  let rest = tail(args, 1)
  match cmd {
    "transform" => cmd_transform(sink, rest)
    "ops" => cmd_ops(sink, rest)
    "grid" => cmd_grid(sink, rest)
    "describe" => cmd_describe(sink, rest)
    "wkt" => cmd_wkt(sink, rest)
    "proj" => cmd_proj(sink, rest)
    "list" => cmd_list(sink, rest)
    "search" => cmd_search(sink, rest)
    "help" | "--help" | "-h" => {
      print_help(sink)
      EXIT_OK
    }
    "version" | "--version" => {
      sink.line("mooncrs " + version())
      EXIT_OK
    }
    _ => {
      sink.note("错误: 未知命令 '" + cmd + "'")
      sink.note("可用的命令：" + join_lines(command_names()))
      sink.note("用法: mooncrs <命令> [参数...]")
      print_help(sink)
      EXIT_USAGE
    }
  }
}

///|
/// 版本号。与 `moon.mod` 保持一致。
fn version() -> String {
  "0.1.0"
}

///|
/// 帮助。
pub fn print_help(sink : Sink) -> Unit {
  sink.line("mooncrs " + version() + " — 坐标参考系转换引擎")
  sink.line("")
  sink.line("用法: mooncrs <命令> [参数...]")
  sink.line("")
  sink.line("命令:")
  sink.line("  transform [--grid ID=PATH] [--explain] <源> <目标> <x> <y> [...]")
  sink.line("                                      坐标转换")
  sink.line("  ops --from <源> --to <目标> [--point <x> <y>]")
  sink.line("                                      列出候选运算及其适用性")
  sink.line("  grid <文件.gsb> [<lon> <lat> ...]   查看网格数据与改正量")
  sink.line("  describe <CRS>                      查看坐标系定义")
  sink.line("  wkt <CRS>                           输出 WKT2")
  sink.line("  proj <CRS>                          输出 PROJ 串")
  sink.line("  list [起始] [结束]                  列出内置 EPSG 码")
  sink.line("  search <关键词>                     按名称搜索")
  sink.line("  version                             版本号")
  sink.line("")
  sink.line("CRS 可以用四种写法之一：")
  sink.line("  EPSG:4326                            注册表引用")
  sink.line("  32650                                裸码")
  sink.line("  +proj=utm +zone=50 +datum=WGS84      PROJ 串")
  sink.line("  PROJCRS[\"...\",...]                 WKT2 / WKT1")
  sink.line("")
  sink.line("退出码: 0 成功 / 1 参数错误 / 2 可恢复错误（换输入可成功）")
  sink.line("")
  sink.line("示例:")
  sink.line("  mooncrs transform EPSG:4326 EPSG:3857 116.3912 39.9075")
  sink.line("  mooncrs transform 4326 32650 116.3912 39.9075")
  sink.line("  mooncrs ops --from EPSG:4277 --to EPSG:4258 --point 1.7179 52.6576")
  sink.line("  含空格的参数需要加引号，例如 WKT 或 PROJ 串。")
}

///|
/// 拼行。空集合给空串，不给一个空行——否则 `mooncrs version` 之后会多一个
/// 空白行，管道里看着像错误。
fn join_lines(items : Array[String]) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < items.length() {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(items[i])
    i = i + 1
  }
  sb.to_string()
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
/// 统一的错误输出。
pub fn report(sink : Sink, err : @types.CrsError) -> Unit {
  sink.line("错误: " + @types.CrsError::message(err))
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
/// 入口。
///
/// 三层：算（dispatch）→ 打印 → 设退出码。`process_exit` 之后不再有语句，
/// 所以打印必须在它前面完成，否则管道里的输出会丢。
///|
/// 跑一次：算 → 打印 → 设退出码。
///
/// 打印必须在 `process_exit` 之前完成，否则管道里的输出会丢。
pub fn run(raw_args : Array[String]) -> Unit {
  let result = dispatch(strip_program(raw_args))
  if result.out.length() > 0 {
    println(result.out)
  }
  if result.err.length() > 0 {
    eprintln(result.err)
  }
  if result.code != EXIT_OK {
    process_exit(result.code)
  }
}

///|
/// 剥掉运行时的程序路径。
///
/// `@env.args()` 的第一个元素是程序自身，但 js-node 下是 `[node 路径, 脚本路径,
/// 用户参数…]`，比 wasm / native 多一层。判据是"看着像路径"而不是"位置固定"，
/// 所以这里循环剥，直到第一个参数不像路径为止；用户在终端里敲的命令名不会是
/// 路径形态，不会被误剥。
fn strip_program(args : Array[String]) -> Array[String] {
  let mut rest = args
  let mut depth = 0
  while rest.length() > 0 && looks_like_program(rest[0]) && depth < 2 {
    rest = tail(rest, 1)
    depth = depth + 1
  }
  rest
}

///|
fn looks_like_program(token : String) -> Bool {
  token.contains("/") ||
  token.contains("\\") ||
  token.has_suffix(".wasm") ||
  token.has_suffix(".exe") ||
  token.has_suffix(".js") ||
  token.has_suffix(".mjs")
}

///|
/// 设置进程退出码。
///
/// 标准库里没有公开的 `exit`：core 自己在 `argparse` 里用同样的方式声明了
/// 一个私有版本。这里按目标平台各声明一次，是唯一能在 wasm / native 上同时
/// 生效的写法——只 `panic` 的话，所有失败都会变成同一个退出码，脚本无法区分。
#cfg(target="wasm-gc")
fn process_exit(code : Int32) = "__moonbit_sys_unstable" "exit"

///|
#cfg(target="wasm")
fn process_exit(code : Int32) = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn process_exit(code : Int32) = "exit"

///|
#cfg(any(target="js", target="js-node"))
extern "js" fn process_exit(code : Int32) -> Unit = "(c) => { if (typeof process !== 'undefined' && process.exit) { process.exit(c) } }"
