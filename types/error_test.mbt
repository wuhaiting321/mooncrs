// 错误消息的"可操作性"测试。
//
// 这一组不测"算得对不对"，只测"说人话没有"：消息够不够长、有没有告诉用户
// 下一步做什么。判定标准由 `CrsError::is_actionable` 给出——它本身也是被
// 测试的对象，所以这里先用"人写的期望"（长度 + 关键词）再做一遍，避免
// 实现与判定标准一起错、还互相点头。

///|
test "六类错误即使正文很短，也会补上可操作建议" {
  let cases : Array[@types.CrsError] = [
    @types.CrsError::Parse("语法断了"),
    @types.CrsError::Invalid("数值不对"),
    @types.CrsError::UnsupportedProjection("奇怪投影"),
    @types.CrsError::UnsupportedOperation("unsupported"),
    @types.CrsError::NotFound("没有这个码"),
    @types.CrsError::Domain("算不出来"),
  ]
  for e in cases {
    let m = e.message()
    // 短正文 + 通用建议，必须超过 20 个字符，否则等于没说
    assert_true(m.length() > 20)
    // 至少有一条"下一步"：请 / 改用 / 需要 …
    assert_true(
      m.contains("请") || m.contains("改用") || m.contains("需要") || m.contains("可"),
    )
  }
}

///|
test "裸 unsupported 不会被原样吐给用户" {
  for kind in [
    @types.CrsError::UnsupportedOperation("unsupported"),
    @types.CrsError::UnsupportedOperation("not supported"),
  ] {
    let m = kind.message()
    assert_true(m != "不支持的转换: unsupported")
    assert_true(m != "不支持的转换: not supported")
    assert_true(m.length() > 20)
  }
}

///|
test "正文已经可操作时不再追加建议，避免同一句说两遍" {
  let e = @types.CrsError::NotFound("EPSG:9999 未收录于内置注册表，请改用 WKT2 或 PROJ 串")
  assert_eq(e.message(), "未找到: EPSG:9999 未收录于内置注册表，请改用 WKT2 或 PROJ 串")
}

///|
test "正文以句号结尾时不重复加句号" {
  let e = @types.CrsError::Invalid("椭球长半轴必须为正。")
  let m = e.message()
  assert_true(!m.contains("。。"))
}

///|
test "类别前缀保留，调用方仍能按类别分流" {
  assert_true(@types.CrsError::Parse("x").message().has_prefix("解析失败: "))
  assert_true(@types.CrsError::Invalid("x").message().has_prefix("参数非法: "))
  assert_true(
    @types.CrsError::UnsupportedProjection("x").message().has_prefix("不支持的投影: "),
  )
  assert_true(
    @types.CrsError::UnsupportedOperation("x").message().has_prefix("不支持的转换: "),
  )
  assert_true(@types.CrsError::NotFound("x").message().has_prefix("未找到: "))
  assert_true(@types.CrsError::Domain("x").message().has_prefix("超出定义域: "))
}
