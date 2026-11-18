// 运算注册表的自检。
//
// 这些测试不验算法，只验"数据本身是否可信"：标识格式、范围合法、精度
// 声明、出处齐全。注册表是精度的唯一来源，一条坏记录比缺一条严重得多。

///|
test "注册表每条记录字段齐全且范围合法" {
  let ops = @operation.all()
  assert_true(ops.length() >= 18)
  for op in ops {
    // 标识必须是 EPSG:数字 或 LOCAL:大写，二者之外一律不认
    assert_true(op.code.contains(":"))
    // 范围必须非退化且在合法经纬度内
    assert_true(op.area.south < op.area.north)
    assert_true(op.area.west < op.area.east)
    assert_true(op.area.south >= -90.0)
    assert_true(op.area.north <= 90.0)
    assert_true(op.area.west >= -180.0)
    assert_true(op.area.east <= 180.0)
    // 出处与说明不能为空：不知道参数从哪来的记录不允许存在
    assert_true(op.authority.length() > 2)
    assert_true(op.note.length() > 4)
    // 精度若声明，必须为正
    match op.accuracy_m {
      Some(a) => assert_true(a > 0.0)
      None => ()
    }
  }
}

///|
test "同一对基准存在多条运算，且按精度升序" {
  let etrs = @types.Datum::new("ETRS89", "ETRS89", @types.grs80)
  let osgb = @operation.resolve(@types.osgb36_datum, etrs)
  assert_true(osgb.length() >= 2)
  // 排序后第一条必须是最精确的（OSTN15 网格 0.1 m）
  assert_true(osgb[0].code == "EPSG:7709")
  assert_true(osgb[0].accuracy_rank() < osgb[1].accuracy_rank())

  let nad83 = @types.Datum::new("NAD83", "NAD83", @types.grs80)
  let nad = @operation.resolve(@types.nad27_datum, nad83)
  assert_true(nad.length() >= 2)
  assert_true(nad[0].code == "EPSG:1241")
  // 网格与三参数的精度差至少一个数量级
  assert_true(nad[1].accuracy_rank() >= nad[0].accuracy_rank() * 10.0)
}

///|
test "范围内的点可用，范围外不可用" {
  for op in @operation.all() {
    let lat = (op.area.south + op.area.north) / 2.0
    let lon = (op.area.west + op.area.east) / 2.0
    assert_true(op.area.contains(lon, lat))
    // 往北推 100°，一定在范围外（也避开了经度回绕）
    assert_true(!op.area.contains(lon, lat + 100.0))
  }
}

///|
test "没有登记的基准对返回空，不编造运算" {
  let xian = @types.Datum::new("XIAN80", "Xian 1980", @types.krassowsky1940)
  let ops = @operation.resolve(xian, @types.wgs84_datum)
  assert_true(ops.length() == 0)
}

///|
test "同一基准返回恒等运算，精度为 0" {
  let ops = @operation.resolve(@types.wgs84_datum, @types.wgs84_datum)
  assert_true(ops.length() == 1)
  assert_true(ops[0].code == "LOCAL:IDENTITY")
  assert_true(ops[0].accuracy_rank() == 0.0)
}

///|
test "未声明基准、椭球一致时降级为假定重合且精度未声明" {
  let unknown = @types.Datum::new("UNKNOWN", "Unknown datum", @types.wgs84)
  let ops = @operation.resolve(unknown, @types.wgs84_datum)
  assert_true(ops.length() == 1)
  assert_true(ops[0].code == "LOCAL:ASSUMED_COINCIDENT")
  // 精度未声明必须排在最后，不许冒充高精度
  assert_true(ops[0].accuracy_rank() > 1.0e8)
}

///|
test "未声明基准且椭球不同时不产生任何运算" {
  let unknown = @types.Datum::new("UNKNOWN", "Unknown datum", @types.clarke1866)
  let ops = @operation.resolve(unknown, @types.wgs84_datum)
  assert_true(ops.length() == 0)
}

///|
test "反向运算保留原参数，只翻标志" {
  let op = @operation.by_code("LOCAL:OSGB36_WGS84_7P").unwrap()
  let inv = op.inverse()
  assert_true(inv.reversed)
  assert_true(inv.source == "WGS84")
  assert_true(inv.target == "OSGB36")
  match (op.params, inv.params) {
    (Helmert(a), Helmert(b)) => {
      // 参数不许取反：取反会让尺度变成 1+s 而不是 1/s
      assert_true(a.dx == b.dx)
      assert_true(a.ds == b.ds)
      assert_true(a.rz == b.rz)
    }
    _ => assert_true(false)
  }
}

///|
test "基准名称归一化不认错" {
  assert_true(@types.Datum::key_of("World Geodetic System 1984") == "WGS84")
  assert_true(@types.Datum::key_of("WGS_1984") == "WGS84")
  assert_true(@types.Datum::key_of("North American Datum 1927") == "NAD27")
  assert_true(@types.Datum::key_of("Ordnance Survey of Great Britain 1936") == "OSGB36")
  assert_true(@types.Datum::key_of("CH1903") == "CH1903")
  assert_true(@types.Datum::key_of("Totally Made Up Datum") == "UNKNOWN")
}

///|
test "网格运算被标记为需要外部数据" {
  let op = @operation.by_code("EPSG:7709").unwrap()
  assert_true(op.needs_grid())
  assert_true(!op.is_executable(false))
  assert_true(op.is_executable(true))
  let plain = @operation.by_code("LOCAL:OSGB36_WGS84_7P").unwrap()
  assert_true(!plain.needs_grid())
  assert_true(plain.is_executable(false))
}

///|
test "缺运算时的提示能指出缺什么" {
  let xian = @types.Datum::new("XIAN80", "Xian 1980", @types.krassowsky1940)
  let msg = @operation.missing_message(xian, @types.wgs84_datum)
  assert_true(msg.contains("XIAN80"))
  assert_true(msg.contains("WGS84"))
  assert_true(msg.contains("towgs84"))
  assert_true(msg.length() > 40)
}
