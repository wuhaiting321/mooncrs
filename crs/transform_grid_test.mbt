// 网格运算在管道里的联动测试。
//
// 这里用**合成的网格对象**（直接构造 `Ntv2Grid`，不经过解析），验证的是
// 联动：注册表里有网格类运算、用户提供了同标识的数据、管道于是改走网格。
// 网格本身的解析与插值由 `grid` 包的测试负责，两者不重复。
//
// 真实 .gsb 文件的端到端校验放在 docs/DATA.md：那需要一份第三方数据，
// 不适合塞进仓库。

///|
/// 覆盖英国、改正量恒为 +0.5″ 纬的合成网格。
///
/// 标识故意取注册表里 OSTN15 的那个名字：这条测试要的就是"用户按
/// 注册表要求的名字提供数据，管道就认得"。
fn uk_test_grid() -> @grid.Ntv2Grid {
  let cells = FixedArray::make(16, 0.0F)
  let mut k = 0
  while k < 4 {
    cells[k * 4] = 0.5F
    k = k + 1
  }
  let sub : @grid.SubGrid = {
    name: "TESTUK",
    parent: "NONE",
    south: 49.0,
    west: -8.0,
    north: 55.0,
    east: 2.0,
    lat_inc: 6.0,
    lon_inc: 10.0,
    nrows: 2,
    ncols: 2,
    cells,
  }
  {
    name: "OSTN15_NTv2_OSGBtoETRS",
    version: "NTv2.0",
    from_system: "TEST",
    to_system: "TEST",
    from_ellipsoid: (6377563.396, 6356256.909),
    to_ellipsoid: (6378137.0, 6356752.314140356),
    lon_convention: "west-positive",
    subs: [sub],
  }
}

///|
/// 未加载网格时，报告必须说清"缺哪个文件、去哪里拿"，而不是只说"不支持"。
test "未加载网格时报错指出缺哪个文件" {
  let from = @epsg.get(4277)
  let to = @epsg.get(4258)
  let r = @crs.transform_report(from, to, 1.7179, 52.6576)
  assert_true(r.2.skipped.length() > 0)
  let mut found = false
  for s in r.2.skipped {
    if s.contains("OSTN15_NTv2_OSGBtoETRS") && s.contains("docs/DATA.md") {
      found = true
    }
  }
  assert_true(found)
}

///|
/// 提供了同名网格之后，网格运算成为候选，并因精度更高被优先选中。
test "提供网格后改走网格运算" {
  let grids = @grid.GridSet::empty()
  grids.add("OSTN15_NTv2_OSGBtoETRS", uk_test_grid())
  let from = @epsg.get(4277)
  let to = @epsg.get(4258)
  let r = @crs.transform_report(from, to, 1.7179, 52.6576, grids=grids)
  // 网格给的是 +0.5″ 纬，经不变
  assert_true((r.0 - 1.7179).abs() < 1.0e-12)
  assert_true((r.1 - (52.6576 + 0.5 / 3600.0)).abs() < 1.0e-12)
  assert_eq(r.2.operation.code, "EPSG:7709")
  assert_true(r.2.skipped.length() == 0)
}

///|
/// 网格不覆盖该点时必须报错，并带出网格的覆盖范围。
///
/// 这里不降级到低精度路径：静默换一条算得出来但精度差两个数量级的路径，
/// 等于把"数据不够"伪装成"算完了"。
test "点超出网格覆盖时给出范围" {
  let grids = @grid.GridSet::empty()
  grids.add("OSTN15_NTv2_OSGBtoETRS", uk_test_grid())
  let from = @epsg.get(4277)
  let to = @epsg.get(4258)
  let mut caught = false
  try {
    let _ = @crs.transform(from, to, 0.0, 58.0, grids=grids)
  } catch {
    err => {
      caught = true
      let m = err.message()
      assert_true(m.contains("覆盖范围"))
      assert_true(m.contains("TESTUK") || m.contains("网格"))
    }
  }
  assert_true(caught)
}

///|
/// NADCON 运算要说"格式没实现"，不能说"缺数据"——这两件事的解决办法
/// 完全不同：前者等实现，后者去下载。
test "NADCON 运算报格式未实现" {
  let grids = @grid.GridSet::empty()
  // 即使把同名文件塞进来，也不能假装能用
  grids.add("conus", uk_test_grid())
  let from = @epsg.get(4267)
  let to = @epsg.get(4269)
  let r = @crs.transform_report(from, to, -96.0, 32.0, grids=grids)
  let mut found = false
  for s in r.2.skipped {
    if s.contains("NADCON") && s.contains("NTv2") {
      found = true
    }
  }
  assert_true(found)
  // 仍然落到三参数路径上
  assert_true(r.2.operation.code.contains("NAD27"))
}

///|
/// 同一输入两次运行必须逐字一致（网格路径也不能引入顺序依赖）。
test "网格路径结果可复现" {
  let grids = @grid.GridSet::empty()
  grids.add("OSTN15_NTv2_OSGBtoETRS", uk_test_grid())
  let from = @epsg.get(4277)
  let to = @epsg.get(4258)
  let a = @crs.transform(from, to, -1.5, 54.3, grids=grids)
  let b = @crs.transform(from, to, -1.5, 54.3, grids=grids)
  assert_eq(a.0, b.0)
  assert_eq(a.1, b.1)
}
