// PROJ 串解析与生成测试。
//
// 重点不是"能不能解析"，而是"解析后语义对不对"：`+zone=33` 必须变成
// 中央经线 15°、`+south` 必须变成假北 1000 万米。这些隐性换算错了，
// 表面上一切正常，坐标却整体偏移几百公里。

///|
/// 基本键值解析。
test "解析键值对" {
  let params = @projstr.parse("+proj=utm +zone=33 +datum=WGS84 +units=m")
  assert_true(params.get("proj").unwrap() == "utm")
  assert_true(params.get("datum").unwrap() == "WGS84")
  assert_true(params.get_double("zone").unwrap() == 33.0)
  assert_true(params.keys().length() == 4)
}

///|
/// 标志型参数：`+south` 不带值。
test "标志型参数" {
  let params = @projstr.parse("+proj=utm +zone=50 +south")
  assert_true(params.flag("south"))
  assert_true(!params.flag("north"))
  // 显式否定义
  let off = @projstr.parse("+proj=utm +zone=50 +south=no")
  assert_true(!off.flag("south"))
}

///|
/// `+towgs84` 的逗号列表。
test "towgs84 解析" {
  let params = @projstr.parse("+proj=longlat +ellps=airy +towgs84=446.448,-125.157,542.06,0.1502,0.247,0.8421,-20.4894")
  match params.get("towgs84") {
    Some(raw) => assert_true(raw.contains("542.06"))
    None => assert_true(false)
  }
  let crs = @projstr.to_crs(params)
  match crs {
    Geographic(g) =>
      match g.datum.to_wgs84 {
        Some(h) => {
          assert_true((h.dx - 446.448).abs() < 1.0e-9)
          assert_true((h.ds + 20.4894).abs() < 1.0e-9)
        }
        None => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// `+zone` 必须展开成中央经线；这是最容易漏的隐性换算。
test "UTM 带号展开为中央经线" {
  let crs = @projstr.to_crs(@projstr.parse("+proj=utm +zone=33 +datum=WGS84"))
  match crs {
    Projected(p) => {
      assert_true(p.method_code == 9807)
      match p.param_by_code(8802) {
        Some(lon0) => assert_true((lon0 - 15.0).abs() < 1.0e-12)
        None => assert_true(false)
      }
      match p.param_by_code(8805) {
        Some(k0) => assert_true((k0 - 0.9996).abs() < 1.0e-12)
        None => assert_true(false)
      }
      match p.param_by_code(8807) {
        Some(fnorth) => assert_true(fnorth == 0.0)
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// 南半球：假北应为 10000000。
test "南半球 UTM 假北" {
  let crs = @projstr.to_crs(@projstr.parse("+proj=utm +zone=50 +south +datum=WGS84"))
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
/// 方法推导：有 `+lat_ts` 的墨卡托是 variant B。
test "墨卡托 variant 推导" {
  let a = @projstr.to_crs(@projstr.parse("+proj=merc +lon_0=0 +k=1 +ellps=WGS84"))
  let b = @projstr.to_crs(@projstr.parse("+proj=merc +lon_0=0 +lat_ts=42 +ellps=WGS84"))
  match a {
    Projected(p) => assert_true(p.method_code == 9804)
    _ => assert_true(false)
  }
  match b {
    Projected(p) => assert_true(p.method_code == 9805)
    _ => assert_true(false)
  }
}

///|
/// 未知投影必须报错，不能默默当墨卡托。
test "未知投影报错" {
  let ok = try {
    let _ = @projstr.to_crs(@projstr.parse("+proj=moll +lon_0=0"))
    false
  } catch {
    _ => true
  }
  assert_true(ok)
}

///|
/// 缺少 `+proj` 报错。
test "缺少 proj 报错" {
  let ok = try {
    let _ = @projstr.to_crs(@projstr.parse("+ellps=WGS84"))
    false
  } catch {
    _ => true
  }
  assert_true(ok)
}

///|
/// 生成 → 再解析，语义不变。
test "PROJ 串往返一致" {
  let first = @projstr.to_crs(
    @projstr.parse("+proj=tmerc +lat_0=0 +lon_0=117 +k=0.9996 +x_0=500000 +y_0=0 +ellps=WGS84"),
  )
  let text = @projstr.to_proj(first)
  let second = @projstr.to_crs(@projstr.parse(text))
  match first {
    Projected(a) =>
      match second {
        Projected(b) => {
          assert_true(a.method_code == b.method_code)
          assert_true(a.params.length() == b.params.length())
          assert_true((a.unit.factor - b.unit.factor).abs() < 1.0e-18)
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// 生成的串必须能被再次解析出同样的投影（关键字不丢）。
test "PROJ 输出包含关键参数" {
  let crs = @projstr.to_crs(
    @projstr.parse("+proj=lcc +lat_1=25 +lat_2=47 +lat_0=0 +lon_0=105 +x_0=0 +y_0=0 +ellps=GRS80"),
  )
  let text = @projstr.to_proj(crs)
  assert_true(text.contains("+proj=lcc"))
  assert_true(text.contains("+lat_1=25"))
  assert_true(text.contains("+lat_2=47"))
  assert_true(text.contains("+lon_0=105"))
}

///|
/// 数值格式化：整数不带尾零。
test "数值格式化" {
  assert_true(@projstr.fmt(6378137.0) == "6378137")
  assert_true(@projstr.fmt(0.0) == "0")
  assert_true(@projstr.fmt(-2.0) == "-2")
}
