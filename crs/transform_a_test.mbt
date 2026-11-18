// 转换管道的"严格性"测试。
//
// 这一组测的不是"算得准不准"，而是"该失败的时候有没有失败、该提醒的时候
// 有没有提醒"。0.1 版被驳回的核心问题就在这里：它能算出数，但算错时不说话。

///|
/// 两点间近似地面距离（米）。测试文件各自持有副本，避免依赖另一个
/// 测试文件里的私有函数。
fn dist_m(lon1 : Double, lat1 : Double, lon2 : Double, lat2 : Double) -> Double {
  let a = 6378137.0
  let rad = 3.141592653589793 / 180.0
  let dlat = (lat2 - lat1) * rad
  let dlon = (lon2 - lon1) * rad * @math.cos(lat1 * rad)
  ((dlat * dlat + dlon * dlon).sqrt()) * a
}

///|
test "同基准转换报告为恒等运算且无保留" {
  let utm = @epsg.get(32650)
  let wgs84 = @epsg.get(4326)
  let (_, _, rep) = @crs.transform_report(wgs84, utm, 117.0, 0.0)
  assert_true(rep.operation.code == "LOCAL:IDENTITY")
  assert_true(rep.is_clean())
  assert_true(rep.warnings.length() == 0)
}

///|
test "无可用运算时 transform 必须报错，只有 ballpark 才降级" {
  // Xian 1980 的定义里没有 +datum，注册表也没有它的运算
  let xian = @epsg.get(4610)
  let wgs84 = @epsg.get(4326)
  let mut message = ""
  let _pair = @crs.transform(xian, wgs84, 116.0, 39.0) catch {
    err => {
      message = err.message()
      (0.0, 0.0)
    }
  }
  assert_true(message.length() > 20)
  assert_true(message.contains("坐标运算"))

  let (_, _, rep) = @crs.transform_ballpark(xian, wgs84, 116.0, 39.0)
  assert_true(rep.operation.code == "LOCAL:BALLPARK")
  assert_true(rep.warnings.length() >= 1)
  assert_true(!rep.is_clean())
}

///|
test "点落在已登记范围外必须报错，并说明范围" {
  // NAD27 只登记了美国本土的运算；阿拉斯加不在范围内
  let nad27 = @epsg.get(4267)
  let wgs84 = @epsg.get(4326)
  let mut message = ""
  let _pair = @crs.transform(nad27, wgs84, -150.0, 61.0) catch {
    err => {
      message = err.message()
      (0.0, 0.0)
    }
  }
  assert_true(message.contains("适用范围"))
  assert_true(message.contains("LOCAL:NAD27_WGS84_CONUS_3P"))
}

///|
test "有更精确的网格运算但缺数据时，报告里要说明跳过了什么" {
  let bng = @epsg.get(27700)
  let etrs = @epsg.get(4258)
  let (_, _, rep) = @crs.transform_report(bng, etrs, 651409.903, 313177.270)
  // 网格版被跳过，实际用的是 7 参数
  assert_true(rep.operation.code == "LOCAL:OSGB36_ETRS89_7P")
  assert_true(rep.skipped.length() == 1)
  assert_true(rep.skipped[0].contains("EPSG:7709"))
  assert_true(rep.skipped[0].contains("网格"))
}

///|
test "定义文本自带的 towgs84 会被采用，但必须标注精度未声明" {
  let custom = @crs.parse(
    "+proj=longlat +ellps=airy +towgs84=446.448,-125.157,542.06,0.1502,0.247,0.8421,-20.4894",
  )
  let wgs84 = @epsg.get(4326)
  let (_, _, rep) = @crs.transform_report(custom, wgs84, 1.7179216, 52.6575703)
  assert_true(rep.operation.code == "LOCAL:INLINE_TOWGS84")
  assert_true(rep.operation.accuracy_m is None)
  assert_true(rep.warnings.length() >= 1)
  assert_true(rep.warnings[0].contains("没有适用范围"))
}

///|
test "定义里没写基准但椭球一致时，按假定重合处理并警告" {
  let bare = @crs.parse("+proj=longlat +ellps=WGS84")
  let wgs84 = @epsg.get(4326)
  let (_, _, rep) = @crs.transform_report(bare, wgs84, 116.0, 39.0)
  assert_true(rep.operation.code == "LOCAL:ASSUMED_COINCIDENT")
  assert_true(rep.warnings.length() >= 1)
  assert_true(!rep.is_clean())
}

///|
test "定义里没写基准且椭球不同，必须报错而不是硬算" {
  let bare = @crs.parse("+proj=longlat +ellps=clrk66")
  let wgs84 = @epsg.get(4326)
  let mut message = ""
  let _pair = @crs.transform(bare, wgs84, -96.0, 28.5) catch {
    err => {
      message = err.message()
      (0.0, 0.0)
    }
  }
  assert_true(message.length() > 20)
}

///|
test "同一输入重复转换，结果与报告逐字一致" {
  let bng = @epsg.get(27700)
  let wgs84 = @epsg.get(4326)
  let a = @crs.transform_report(bng, wgs84, 651409.903, 313177.270)
  let b = @crs.transform_report(bng, wgs84, 651409.903, 313177.270)
  assert_true(a.0 == b.0)
  assert_true(a.1 == b.1)
  assert_true(a.2.to_text() == b.2.to_text())
}

///|
test "跨基准偏移量级正确（OSGB36 约百米级，不能是米级或公里级）" {
  let osgb = @epsg.get(4277)
  let wgs84 = @epsg.get(4326)
  let lon = 1.7179216
  let lat = 52.6575703
  let shifted = @crs.transform(osgb, wgs84, lon, lat)
  let d = dist_m(lon, lat, shifted.0, shifted.1)
  assert_true(d > 50.0)
  assert_true(d < 300.0)
}

///|
test "报告里的步骤按执行顺序列出，且包含实际运算标识" {
  let bng = @epsg.get(27700)
  let wgs84 = @epsg.get(4326)
  let (_, _, rep) = @crs.transform_report(bng, wgs84, 651409.903, 313177.270)
  assert_true(rep.steps.length() >= 3)
  assert_true(rep.steps[rep.steps.length() - 1].contains("正算"))
  let mut hit = false
  for s in rep.steps {
    if s.contains(rep.operation.code) {
      hit = true
    }
  }
  assert_true(hit)
}
