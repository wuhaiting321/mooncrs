///|
/// 最小使用样例：解析两种写法的 CRS，转换一个点，再把这次转换的依据打出来。
///
/// 运行：`moon run examples/basic`
fn main raise {
  // 四种写法都认：EPSG 码、裸码、PROJ 串、WKT
  let from = @crs.parse("EPSG:4326")
  let to = @crs.parse("+proj=utm +zone=50 +datum=WGS84")

  // 单点转换：北京 116.3912°E, 39.9075°N
  let (e, n) = @crs.transform(from, to, 116.3912, 39.9075)
  println("UTM 50N  \{e}, \{n}")

  // 会拿结果去做决定时，用带报告的入口：它给出用的哪条运算、精度、范围、警告
  let (_, _, report) = @crs.transform_report(from, to, 116.3912, 39.9075)
  println("")
  println(report.to_text())
}
