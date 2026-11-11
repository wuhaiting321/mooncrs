// WKT 解析与序列化测试。
//
// 测试数据取自真实文件的常见形态：WKT2 带 ID 与单位、WKT1 的
// `PROJCS`、以及只给名字不给码的"野生"写法。

///|
/// 一份完整的 WKT2 投影坐标系（EPSG:32633 的公开表示）。
let wkt2_utm33 : String =
  #|PROJCRS["WGS 84 / UTM zone 33N",
  #|    BASEGEOGCRS["WGS 84",
  #|        DATUM["World Geodetic System 1984",
  #|            ELLIPSOID["WGS 84",6378137,298.257223563,
  #|                LENGTHUNIT["metre",1]]],
  #|        PRIMEM["Greenwich",0,
  #|            ANGLEUNIT["degree",0.0174532925199433]],
  #|        ID["EPSG",4326]],
  #|    CONVERSION["UTM zone 33N",
  #|        METHOD["Transverse Mercator",
  #|            ID["EPSG",9807]],
  #|        PARAMETER["Latitude of natural origin",0,
  #|            ANGLEUNIT["degree",0.0174532925199433],
  #|            ID["EPSG",8801]],
  #|        PARAMETER["Longitude of natural origin",15,
  #|            ANGLEUNIT["degree",0.0174532925199433],
  #|            ID["EPSG",8802]],
  #|        PARAMETER["Scale factor at natural origin",0.9996,
  #|            SCALEUNIT["unity",1],
  #|            ID["EPSG",8805]],
  #|        PARAMETER["False easting",500000,
  #|            LENGTHUNIT["metre",1],
  #|            ID["EPSG",8806]],
  #|        PARAMETER["False northing",0,
  #|            LENGTHUNIT["metre",1],
  #|            ID["EPSG",8807]]],
  #|    CS[Cartesian,2],
  #|        AXIS["(E)",east,ORDER[1]],
  #|        AXIS["(N)",north,ORDER[2]],
  #|        LENGTHUNIT["metre",1],
  #|    ID["EPSG",32633]]

///|
/// WKT1 地理坐标系。
let wkt1_wgs84 : String =
  #|GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,
  #|AUTHORITY["EPSG","7030"]],TOWGS84[0,0,0,0,0,0,0],AUTHORITY["EPSG","6326"]],
  #|PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",
  #|0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]]

///|
/// 解析 WKT2：名称、标识、方法码、参数都应正确。
test "WKT2 解析 UTM 33N" {
  let crs = @wkt.parse(wkt2_utm33)
  assert_true(crs.name() == "WGS 84 / UTM zone 33N")
  match crs.identifier() {
    Some(id) => assert_true(id.to_text() == "EPSG:32633")
    None => assert_true(false)
  }
  match crs {
    Projected(p) => {
      assert_true(p.method_name == "Transverse Mercator")
      assert_true(p.method_code == 9807)
      assert_true(p.base.datum.ellipsoid.semi_major == 6378137.0)
      assert_true(p.params.length() == 5)
      match p.param("False easting") {
        Some(v) => assert_true((v - 500000.0).abs() < 1.0e-9)
        None => assert_true(false)
      }
      match p.param_by_code(8805) {
        Some(v) => assert_true((v - 0.9996).abs() < 1.0e-12)
        None => assert_true(false)
      }
      // 轴序：easting/north，投影坐标系默认东-北。
      assert_true(p.axis == @types.EastNorth)
    }
    _ => assert_true(false)
  }
}

///|
/// WKT1 的 `GEOGCS` 与 `TOWGS84` 都要能吃。
test "WKT1 解析 GEOGCS 与 TOWGS84" {
  let crs = @wkt.parse(wkt1_wgs84)
  match crs {
    Geographic(g) => {
      assert_true(g.name == "WGS 84")
      assert_true((g.unit.factor - 0.017453292519943295).abs() < 1.0e-17)
      match g.datum.to_wgs84 {
        Some(h) => assert_true(h.is_identity())
        None => assert_true(false)
      }
      match g.id {
        Some(id) => assert_true(id.code == 4326)
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// WKT1 的 `PROJCS`：方法名是下划线写法，参数名也是，
/// 单位是美国测量英尺——三处都要正确识别。
test "WKT1 解析 PROJCS（美国测量英尺）" {
  let text =
    #|PROJCS["NAD27 / Texas South Central",
    #|GEOGCS["NAD27",DATUM["North_American_Datum_1927",
    #|SPHEROID["Clarke 1866",6378206.4,294.9786982]],
    #|PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]],
    #|PROJECTION["Lambert_Conformal_Conic"],
    #|PARAMETER["standard_parallel_1",28.38333333333333],
    #|PARAMETER["standard_parallel_2",30.28333333333333],
    #|PARAMETER["latitude_of_origin",27.83333333333333],
    #|PARAMETER["central_meridian",-99],
    #|PARAMETER["false_easting",2000000],
    #|PARAMETER["false_northing",0],
    #|UNIT["US survey foot",0.3048006096012192]]
  let crs = @wkt.parse(text)
  match crs {
    Projected(p) => {
      assert_true(p.method_code == 9802)
      assert_true((p.unit.factor - 0.3048006096012192).abs() < 1.0e-16)
      assert_true(p.base.datum.ellipsoid.semi_major == 6378206.4)
      // WKT1 的 standard_parallel_1 必须能被别名命中
      match p.param("standardparallel1") {
        Some(v) => assert_true((v - 28.38333333333333).abs() < 1.0e-9)
        None => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
/// 括号形式：Shapefile 的 .prj 用圆括号，且常与方括号混用。
test "圆括号与方括号混用" {
  let text = "GEOGCS(\"WGS 84\",DATUM(\"WGS_1984\",SPHEROID(\"WGS 84\",6378137,298.257223563)),PRIMEM(\"Greenwich\",0),UNIT(\"degree\",0.0174532925199433))"
  let crs = @wkt.parse(text)
  assert_true(crs.name() == "WGS 84")
}

///|
/// 序列化 → 再解析，语义应保持不变。
test "WKT2 往返一致" {
  let first = @wkt.parse(wkt2_utm33)
  let text = @wkt.to_wkt2(first)
  let second = @wkt.parse(text)
  assert_true(second.name() == first.name())
  match first {
    Projected(a) =>
      match second {
        Projected(b) => {
          assert_true(a.method_code == b.method_code)
          assert_true(a.params.length() == b.params.length())
          assert_true((b.unit.factor - a.unit.factor).abs() < 1.0e-18)
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
/// 生成的 WKT2 必须带 `ID["EPSG",...]` 与 `ANGLEUNIT`，
/// 这是"能不能被其他软件认回同一个坐标系"的关键。
test "WKT2 输出包含关键结构" {
  let crs = @wkt.parse(wkt2_utm33)
  let text = @wkt.to_wkt2(crs)
  assert_true(text.contains("PROJCRS"))
  assert_true(text.contains("ID[\"EPSG\",32633]"))
  assert_true(text.contains("ANGLEUNIT"))
  assert_true(text.contains("Transverse Mercator"))
}

///|
/// 不支持的类型要明确报错，不能猜。
test "不支持的 WKT 类型报错" {
  let ok = try {
    let _ = @wkt.parse("COMPOUNDCRS[\"x\",GEOGCRS[\"a\"],VERTCRS[\"b\"]]")
    false
  } catch {
    _ => true
  }
  assert_true(ok)
}

///|
/// 语法错误要报错。
test "语法错误报错" {
  let ok = try {
    let _ = @wkt.parse("GEOGCRS[\"unterminated")
    false
  } catch {
    _ => true
  }
  assert_true(ok)
}
