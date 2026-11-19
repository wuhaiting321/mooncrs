// CLI 侧读取 .gsb 文件。
//
// 文件读取只出现在这里：`grid` 包只接受字节，不认识路径。这样同一套解析
// 与插值代码在 wasm / js / native 上跑出来的结果完全一致，也不会因为
// "库里偷偷读了文件"而让 wasm 构建失败。

///|
/// 取子串（按下标）。不用 `String::substring`：它在当前工具链里已弃用，
/// 而字符串视图切片在不同版本间写法还在变——一个十进制下标循环更稳。
fn slice(s : String, from : Int, to : Int) -> String {
  let sb = StringBuilder()
  let mut i = from
  let end = if to > s.length() {
    s.length()
  } else {
    to
  }
  while i < end {
    match s.get_char(i) {
      Some(c) => sb.write_char(c)
      None => ()
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// `--grid` 参数的形态：`--grid PATH` 或 `--grid ID=PATH`。
///
/// 不给 ID 时用文件名去扩展名（`OSTN15_NTv2_OSGBtoETRS.gsb`
/// → `OSTN15_NTv2_OSGBtoETRS`），因为官方数据的分发名就是注册表里的
/// 网格标识，能省一次手写。
fn split_grid_spec(spec : String) -> (String, String) {
  let mut i = 0
  while i < spec.length() {
    match spec.get_char(i) {
      Some(c) =>
        if c == '=' {
          return (slice(spec, 0, i), slice(spec, i + 1, spec.length()))
        }
      None => ()
    }
    i = i + 1
  }
  ("", spec)
}

///|
/// 取路径的文件名并去掉扩展名。
fn stem_of(path : String) -> String {
  let mut start = 0
  let mut i = 0
  while i < path.length() {
    match path.get_char(i) {
      Some(c) =>
        if c == '/' || c == '\\' {
          start = i + 1
        }
      None => ()
    }
    i = i + 1
  }
  let name = slice(path, start, path.length())
  let mut dot = name.length()
  let mut j = 0
  while j < name.length() {
    match name.get_char(j) {
      Some(c) =>
        if c == '.' {
          dot = j
        }
      None => ()
    }
    j = j + 1
  }
  slice(name, 0, dot)
}

///|
/// 读取并登记一个网格。失败时把原因写进 sink 并返回 `false`，
/// 由调用方决定是否继续。
fn load_grid(sink : Sink, spec : String, grids : @grid.GridSet) -> Bool {
  let pair = split_grid_spec(spec)
  let id = if pair.0 == "" {
    stem_of(pair.1)
  } else {
    pair.0
  }
  let path = pair.1
  if path == "" {
    sink.line("错误: --grid 后面缺少文件路径")
    sink.line("写法: --grid <ID>=<路径.gsb>，例如 --grid conus=conus.gsb")
    return false
  }
  let bytes = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(m) => {
      sink.line("错误: 读取网格文件失败 '" + path + "'：" + m)
      sink.line("检查路径是否正确；需要哪些网格、从哪下载，见 docs/DATA.md")
      return false
    }
  }
  let grid = @grid.Ntv2Grid::parse(bytes, name=stem_of(path)) catch {
    err => {
      sink.line("错误: " + err.message() + "（文件 " + path + "）")
      return false
    }
  }
  grids.add(id, grid)
  // 走 stderr：stdout 是给管道用的，混进一行提示会让 `| awk` 之类的用法出错。
  sink.note(
    "已加载网格 " +
    id +
    "：" +
    grid.len().to_string() +
    " 个子网格，" +
    grid.lon_convention +
    "，覆盖 " +
    grid.coverage_text(),
  )
  true
}

///|
/// 从参数里摘出 `--grid/-g`，返回其余位置参数。
///
/// 返回 `None` 表示网格加载失败——此时不应继续转换，否则用户会拿到
/// "坐标运算不可用"的报错，而真实原因其实是文件没读进来。
fn collect_grids(
  sink : Sink,
  args : Array[String],
  grids : @grid.GridSet,
) -> Array[String]? {
  let rest : Array[String] = []
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--grid" || a == "-g" {
      if i + 1 >= args.length() {
        sink.line("错误: --grid 后面缺少文件路径")
        sink.line("写法: --grid <ID>=<路径.gsb>，例如 --grid conus=conus.gsb")
        return None
      }
      if !load_grid(sink, args[i + 1], grids) {
        return None
      }
      i = i + 2
    } else if a.has_prefix("--grid=") {
      if !load_grid(sink, slice(a, 7, a.length()), grids) {
        return None
      }
      i = i + 1
    } else {
      rest.push(a)
      i = i + 1
    }
  }
  Some(rest)
}

///|
/// `grid <文件> [<lon> <lat> ...]`：查看网格，或在网格上取改正量。
///
/// 存在的理由很实际：拿到一个 .gsb 之后，第一件要确认的事是"它盖不盖
/// 我要用的地方"。等到转换时报"点不在范围内"才知道，代价太高。
fn cmd_grid(sink : Sink, args : Array[String]) -> Int32 {
  if args.length() < 1 {
    sink.line("用法: mooncrs grid <文件.gsb> [<lon> <lat> ...]")
    sink.line("不给坐标时只打印网格摘要；给了坐标则输出该点的改正量（角秒）")
    sink.line("示例: mooncrs grid OSTN15_NTv2_OSGBtoETRS.gsb -1.7160 52.6579")
    return EXIT_USAGE
  }
  let path = args[0]
  let bytes = @fs.read_file_to_bytes(path) catch {
    @fs.IOError(m) => {
      sink.line("错误: 读取网格文件失败 '" + path + "'：" + m)
      sink.line("检查路径是否正确；需要哪些网格、从哪下载，见 docs/DATA.md")
      return EXIT_FAILED
    }
  }
  let grid = @grid.Ntv2Grid::parse(bytes, name=stem_of(path)) catch {
    err => {
      sink.line("错误: " + err.message())
      return EXIT_FAILED
    }
  }
  sink.line("文件    " + path)
  sink.line("版本    " + grid.version + "（经度约定 " + grid.lon_convention + "）")
  sink.line(
    "椭球    源 a=" +
    show(grid.from_ellipsoid.0) +
    " b=" +
    show(grid.from_ellipsoid.1) +
    "；目标 a=" +
    show(grid.to_ellipsoid.0) +
    " b=" +
    show(grid.to_ellipsoid.1),
  )
  sink.line("子网格  " + grid.len().to_string() + " 个")
  for s in grid.subs {
    sink.line(
      "  " +
      s.name +
      "  " +
      s.nrows.to_string() +
      " 行 × " +
      s.ncols.to_string() +
      " 列，格距 " +
      show(s.lat_inc * 3600.0) +
      "″ × " +
      show(s.lon_inc * 3600.0) +
      "″，" +
      s.to_text(),
    )
  }
  sink.line("覆盖    " + grid.coverage_text())
  let mut failed = false
  if args.length() >= 3 {
    let mut i = 1
    while i + 1 < args.length() {
      match (@projstr.parse_float(args[i]), @projstr.parse_float(args[i + 1])) {
        (Some(lon), Some(lat)) =>
          match grid.forward(lon, lat) {
            Some(shift) =>
              sink.line(
                show(lon) +
                " " +
                show(lat) +
                " → 纬改正 " +
                show(shift.dlat * 3600.0) +
                "″  经改正 " +
                show(shift.dlon * 3600.0) +
                "″  子网格 " +
                shift.subgrid,
              )
            None => {
              sink.line(
                "错误: " +
                grid.outside_message(lon, lat) +
                "（该点不在任何子网格内；网格不会外推，超出范围没有改正量）",
              )
              failed = true
            }
          }
        _ => {
          sink.line("错误: 无法解析坐标 '" + args[i] + "' 或 '" + args[i + 1] + "'")
          sink.line("这两个参数应当是十进制数值，例如 `-1.7160 52.6579`")
          failed = true
        }
      }
      i = i + 2
    }
  }
  if failed {
    EXIT_FAILED
  } else {
    EXIT_OK
  }
}
