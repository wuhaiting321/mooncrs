// 网格解析失败的文案测试。
//
// `.gsb` 是二进制文件，用户拿到报错后最常见的反应是"文件坏了？还是版本不对？"
// 所以消息里必须出现"哪个字节位置/哪条记录不对"，并指向 docs/DATA.md。
// 判定与别的错误一致：长度够、有下一步。

///|
test "空文件、垃圾字节、截断文件的报错都能直接照着改" {
  let empty : Array[Byte] = []
  let junk : Array[Byte] = []
  let mut i = 0
  while i < 300 {
    junk.push((0xAB).to_byte())
    i = i + 1
  }
  let trunc = capture_bytes(build_gsb([small_spec()], linear_field, cut=400))
  let cases : Array[String] = [
    capture_bytes(Bytes::from_array(empty)),
    capture_bytes(Bytes::from_array(junk)),
    trunc,
  ]
  for m in cases {
    assert_true(m.length() > 20)
    assert_true(m.contains("请") || m.contains("需要") || m.contains("见 docs/DATA.md"))
  }
  // 截断文件要说清"差多少"，否则用户不知道该重新下载还是换工具
  assert_true(trunc.contains("字节") || trunc.contains("截断"))
}

///|
/// 解析一段字节并返回错误消息；没抛错返回空串。
fn capture_bytes(bytes : Bytes) -> String {
  try {
    let _ = @grid.Ntv2Grid::parse(bytes)
    ""
  } catch {
    e => e.message()
  }
}
