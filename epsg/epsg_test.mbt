// EPSG 注册表测试。
//
// 注册表的正确性靠三件事守住：名称对得上、参数对得上、公式族生成的
// 码族（UTM / CGCS2000 三度带）的带号换算对得上。第三类最容易错，
// 因为它是"算出来的"而不是"抄下来的"。

///|
/// 地理坐标系。
test "EPSG:4326" {
  let crs = @epsg.get(4326)
  assert_true(crs.name() == "WGS 84")
  match crs {
    Geographic(g) => {
      assert_true(g.datum.ellipsoid.semi_major == 6378137.0)
      assert_true((g.unit.factor - 0.017453292519943295).abs() < 1.0e-18)
    }
    _ => assert_true(false)
  }
  match crs.identifier() {
    Some(id) => assert_true(id.to_text() == "EPSG:4326")
    None => assert_true(false)
  }
}

///|
/// 投影坐标系：UTM 33N。
test "EPSG:32633" {
  let crs = @epsg.get(32633)
  match crs {
    Projected(p) => {
      assert_true(p.method_code == 9807)
      match p.param_by_code(8802) {
        Some(lon0) => assert_true((lon0 - 15.0).abs() < 1.0e-12)
        None => assert_true(false)
      }
      match p.param_by_code(8806) {
        Some(fe) => assert_true((fe - 500000.0).abs() < 1.0e-9)
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// 南半球 UTM 的假北。
test "EPSG:32750 南半球" {
  let crs = @epsg.get(32750)
  match crs {
    Projected(p) =>
      match p.param_by_code(8807) {
        Some(fnorth) => assert_true((fnorth - 10000000.0).abs() < 1.0e-6)
        None => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// CGCS2000 三度带：带号 → 中央经线。
test "CGCS2000 三度带" {
  // EPSG:4491 = CM 75E；每 +1 码中央经线 +3°
  let crs = @epsg.get(4491)
  match crs {
    Projected(p) =>
      match p.param_by_code(8802) {
        Some(lon0) => assert_true((lon0 - 75.0).abs() < 1.0e-12)
        None => assert_true(false)
      }
    _ => assert_true(false)
  }
  let crs2 = @epsg.get(4511)
  match crs2 {
    Projected(p) =>
      match p.param_by_code(8802) {
        Some(lon0) => assert_true((lon0 - 135.0).abs() < 1.0e-12)
        None => assert_true(false)
      }
    _ => assert_true(false)
  }
  // 带号版：EPSG:4513 = zone 25（CM 75E），假东 = 25*1e6 + 500000
  let crs3 = @epsg.get(4513)
  match crs3 {
    Projected(p) => {
      match p.param_by_code(8802) {
        Some(lon0) => assert_true((lon0 - 75.0).abs() < 1.0e-12)
        None => assert_true(false)
      }
      match p.param_by_code(8806) {
        Some(fe) => assert_true((fe - 25500000.0).abs() < 1.0e-3)
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// 全球 Web Mercator。
test "EPSG:3857" {
  let crs = @epsg.get(3857)
  match crs {
    Projected(p) => assert_true(p.method_code == 1024)
    _ => assert_true(false)
  }
}

///|
/// 未收录的码要报错。
test "未收录的码" {
  assert_true(!@epsg.has(99999))
  let ok = try {
    let _ = @epsg.get(99999)
    false
  } catch {
    _ => true
  }
  assert_true(ok)
}

///|
/// 收录规模：至少 200 个码，且覆盖若干关键族。
test "注册表规模" {
  let codes = @epsg.all_codes()
  assert_true(codes.length() >= 200)
  assert_true(@epsg.has(4326))
  assert_true(@epsg.has(27700))
  assert_true(@epsg.has(4547) || @epsg.has(4491))
}

///|
/// 按名称搜索。
test "搜索" {
  let hits = @epsg.search("UTM 33")
  let mut found = false
  for hit in hits {
    if hit.0 == 32633 {
      found = true
    }
  }
  assert_true(found)
  let british = @epsg.search("british national")
  assert_true(british.length() == 1)
}
