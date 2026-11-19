// 真实失败分支的文案测试。
//
// 与 `types/error_test.mbt` 的分工：那边测"错误类型本身有没有兜底",
// 这边测"库真的跑起来以后，用户看到的是哪句话"。后者更重要——兜底逻辑
// 再漂亮，如果真实分支抛的是 "unsupported"，用户还是什么都不知道。

///|
/// 跑一个会抛错的表达式，返回错误消息；没抛错返回空串。
fn capture(thunk : () -> Unit raise @types.CrsError) -> String {
  try {
    thunk()
    ""
  } catch {
    e => e.message()
  }
}

///|
test "解析类失败：空定义、未知码、未知投影、带号越界" {
  let messages : Array[String] = [
    capture(() => {
      let _ = @crs.parse("")
    }),
    capture(() => {
      let _ = @crs.parse("EPSG:9999")
    }),
    capture(() => {
      let _ = @crs.parse("+proj=nonesuch +datum=WGS84")
    }),
    capture(() => {
      let _ = @crs.parse("+proj=utm +zone=99 +datum=WGS84")
    }),
  ]
  for m in messages {
    assert_true(m.length() > 20)
    assert_true(m.contains("请") || m.contains("改用") || m.contains("可") || m.contains("必须"))
  }
  // 未知码要把码原样回显，否则用户不知道自己把哪一位打错了
  assert_true(messages[1].contains("EPSG:9999"))
  // 带号越界要说清合法范围
  assert_true(messages[3].contains("1..60"))
}

///|
test "转换类失败：无运算、点超范围、定义缺基准" {
  let nad27 = @epsg.get(4267)
  let wgs84 = @epsg.get(4326)
  let xian = @epsg.get(4610)
  let out_of_area = capture(() => {
    let _ = @crs.transform(nad27, wgs84, -150.0, 61.0)
  })
  let no_operation = capture(() => {
    let _ = @crs.transform(xian, wgs84, 116.0, 39.0)
  })
  let bare = @crs.parse("+proj=longlat +ellps=clrk66")
  let unknown_datum = capture(() => {
    let _ = @crs.transform(bare, wgs84, -96.0, 28.5)
  })
  for m in [out_of_area, no_operation, unknown_datum] {
    assert_true(m.length() > 20)
    assert_true(m.contains("请") || m.contains("改用") || m.contains("需要") || m.contains("范围"))
  }
  // 点超范围时，必须把「本来的可用范围」写出来
  assert_true(out_of_area.contains("适用范围"))
  // 缺运算时，必须说清缺的是哪一段（源/目标基准都要出现）
  assert_true(no_operation.contains("Xian") || no_operation.contains("基准"))
}

///|
test "数值定义域失败：纬度超界的消息能指出是哪一步" {
  let wgs84 = @epsg.get(4326)
  let web = @epsg.get(3857)
  let m = capture(() => {
    let _ = @crs.transform(wgs84, web, 116.0, 95.0)
  })
  assert_true(m.length() > 20)
  assert_true(m.contains("纬度"))
  assert_true(m.contains("90"))
}
