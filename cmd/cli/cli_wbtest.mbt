// CLI 的行为测试：输出内容、退出码、确定性。
//
// 这些测试直接调 `dispatch`，不启动进程——`dispatch` 的返回值就是"一次运行
// 的全部产物"，所以"逐字节相同"和"退出码是几"都可以用 `assert` 判定，
// 而不必靠人眼看终端。

///|
/// 按换行切分。
fn lines_of(text : String) -> Array[String] {
  let out : Array[String] = []
  let line = StringBuilder()
  let mut i = 0
  while i < text.length() {
    match text.get_char(i) {
      Some(c) =>
        if c == '\n' {
          out.push(line.to_string())
          line.reset()
        } else {
          line.write_char(c)
        }
      None => ()
    }
    i = i + 1
  }
  out.push(line.to_string())
  out
}

///|
/// 第一条包含 `needle` 的行号，没有则 -1。
fn line_index(lines : Array[String], needle : String) -> Int {
  let mut i = 0
  while i < lines.length() {
    if lines[i].contains(needle) {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 以 `label` 开头的行，返回标签之后的正文。
fn field_text(text : String, label : String) -> String? {
  for line in lines_of(text) {
    if line.has_prefix(label) {
      let mut j = label.length()
      while j < line.length() {
        match line.get_char(j) {
          Some(c) =>
            if c != ' ' {
              return Some(slice_from(line, j))
            }
          None => ()
        }
        j = j + 1
      }
      return Some("")
    }
  }
  None
}

///|
fn slice_from(s : String, from : Int) -> String {
  let sb = StringBuilder()
  let mut i = from
  while i < s.length() {
    match s.get_char(i) {
      Some(c) => sb.write_char(c)
      None => ()
    }
    i = i + 1
  }
  sb.to_string()
}

///|
test "C1 --explain 必含运算/方法/精度/范围/警告五项，且都不为空" {
  let r = dispatch([
    "transform", "--explain", "EPSG:4277", "EPSG:4258", "1.7179", "52.6576",
  ])
  assert_eq(r.code, EXIT_OK)
  for label in ["运算", "方法", "精度", "范围", "警告"] {
    match field_text(r.out, label) {
      Some(v) => assert_true(v.length() > 0)
      None => {
        assert_true(false)
        continue
      }
    }
  }
  // 五项之外还要能看出"这次用的到底是哪条"，光有标签不够。
  assert_true(r.out.contains("LOCAL:OSGB36_ETRS89_7P"))
  assert_true(r.out.contains("EPSG 9606"))
}

///|
test "C1 没有警告时明确写“无”，而不是省略该行" {
  let r = dispatch(["transform", "--explain", "EPSG:4326", "EPSG:32650", "116.3912", "39.9075"])
  assert_eq(r.code, EXIT_OK)
  let lines = lines_of(r.out)
  let i = line_index(lines, "警告")
  assert_true(i >= 0)
  assert_true(lines[i].contains("无"))
}

///|
test "C2 ops 列出全部候选，精度优先排序，逐条标适用性" {
  let r = dispatch([
    "ops", "--from", "EPSG:4277", "--to", "EPSG:4258", "--point", "1.7179", "52.6576",
  ])
  assert_eq(r.code, EXIT_OK)
  let lines = lines_of(r.out)
  let grid_at = line_index(lines, "EPSG:7709")
  let seven_at = line_index(lines, "LOCAL:OSGB36_ETRS89_7P")
  assert_true(grid_at >= 0)
  assert_true(seven_at >= 0)
  // 0.1 m 的网格运算必须排在 2 m 的七参数前面
  assert_true(grid_at < seven_at)
  // 缺数据的那条要标"缺数据"，能用的那条要标"适用于该点"
  assert_true(lines[grid_at].contains("[缺数据]"))
  assert_true(lines[seven_at].contains("[适用于该点]"))
}

///|
test "C2 点超出范围时必须标出来，而不是照样说适用" {
  // NAD27 只登记了美国本土（CONUS）的运算，阿拉斯加不在范围内
  let r = dispatch([
    "ops", "--from", "EPSG:4267", "--to", "EPSG:4326", "--point", "-150.0", "61.0",
  ])
  assert_eq(r.code, EXIT_OK)
  assert_true(r.out.contains("[超出范围]"))
  assert_true(!r.out.contains("[适用于该点]"))
}

///|
test "C2 不存在的基准对要给出可操作提示并以可恢复错误退出" {
  let r = dispatch(["ops", "--from", "EPSG:4610", "--to", "EPSG:4326"])
  assert_eq(r.code, EXIT_FAILED)
  assert_true(r.out.length() > 20)
  assert_true(r.out.contains("错误"))
}

///|
test "C4 同一输入两次运行，输出逐字节相同" {
  let args = ["ops", "--from", "EPSG:4277", "--to", "EPSG:4258", "--point", "1.7179", "52.6576"]
  let a = dispatch(args)
  let b = dispatch(args)
  assert_eq(a.out, b.out)
  assert_eq(a.err, b.err)
  assert_eq(a.code, b.code)

  let explain = ["transform", "--explain", "EPSG:4267", "EPSG:4326", "-96.0", "32.0"]
  let c = dispatch(explain)
  let d = dispatch(explain)
  // 报告里有数组顺序（步骤、已跳过），顺序不稳就会在这里露出来
  assert_eq(c.out, d.out)
}

///|
test "C5 退出码：成功 0 / 参数错 1 / 可恢复错误 2" {
  assert_eq(dispatch(["version"]).code, EXIT_OK)
  assert_eq(
    dispatch(["transform", "EPSG:4326", "EPSG:32650", "116.3912", "39.9075"]).code,
    EXIT_OK,
  )
  // 参数个数不够
  assert_eq(dispatch(["transform", "EPSG:4326"]).code, EXIT_USAGE)
  // 命令名认不出来
  assert_eq(dispatch(["check"]).code, EXIT_USAGE)
  // 缺 --to
  assert_eq(dispatch(["ops", "--from", "EPSG:4277"]).code, EXIT_USAGE)
  // 坐标系不存在
  assert_eq(
    dispatch(["transform", "EPSG:9999", "EPSG:4326", "0", "0"]).code,
    EXIT_FAILED,
  )
  // 坐标不是数值
  assert_eq(
    dispatch(["transform", "EPSG:4326", "EPSG:32650", "116.3912", "abc"]).code,
    EXIT_USAGE,
  )
}

///|
test "用法错误时不往 stdout 写结果，提示写全" {
  let r = dispatch(["transform"])
  assert_eq(r.code, EXIT_USAGE)
  assert_true(r.out.contains("用法:"))
  assert_true(r.out.contains("示例:"))
}
