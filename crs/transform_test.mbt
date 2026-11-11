// 端到端转换测试。
//
// 这是整个项目的验收核心：单看投影公式"算得对"没有意义，必须证明
// 「WKT/PROJ/EPSG 三种输入 → 坐标 → 另一种坐标系」整条链路都对。
// 判据分三层：
//   1. 有公开常量的用常量（如 Web Mercator 世界宽度 20037508.34 m）
//   2. 有闭环的用往返（投影坐标 → 经纬度 → 投影坐标）
//   3. 只能定性的用量级（跨基准偏移应在百米量级）

///|
/// 两点间的近似地面距离（米），用于量级判断。
fn metres_between(lon1 : Double, lat1 : Double, lon2 : Double, lat2 : Double) -> Double {
  let a = 6378137.0
  let rad = 3.141592653589793 / 180.0
  let dlat = (lat2 - lat1) * rad
  let dlon = (lon2 - lon1) * rad * @math.cos(lat1 * rad)
  ((dlat * dlat + dlon * dlon).sqrt()) * a
}

///|
/// 全球常量：Web Mercator 在经度 ±180° 处的横坐标是半个世界宽度。
test "Web Mercator 世界宽度" {
  let wgs84 = @epsg.get(4326)
  let merc = @epsg.get(3857)
  let xy = @crs.transform(wgs84, merc, 180.0, 0.0)
  assert_true((xy.0 - 20037508.342789244).abs() < 1.0e-6)
  assert_true(xy.1.abs() < 1.0e-9)
  // 反算回到 180°。注意经度归一化会把 +180° 折到 -180°，
  // 两者是同一个子午线，测试必须同时接受——这是所有坐标库的共同约定。
  let back = @crs.transform(merc, wgs84, xy.0, xy.1)
  let wrapped = (back.0 - 180.0).abs() < 1.0e-9 || (back.0 + 180.0).abs() < 1.0e-9
  assert_true(wrapped)
  assert_true(back.1.abs() < 1.0e-9)
}

///|
/// 中央经线上横坐标等于假东（UTM 50 带中央经线 117°）。
test "UTM 50 带中央经线" {
  let wgs84 = @epsg.get(4326)
  let utm50 = @epsg.get(32650)
  let xy = @crs.transform(wgs84, utm50, 117.0, 0.0)
  assert_true((xy.0 - 500000.0).abs() < 1.0e-6)
  assert_true(xy.1.abs() < 1.0e-6)
}

///|
/// 地理 ↔ 投影 往返（WGS84 UTM）。
test "UTM 往返" {
  let wgs84 = @epsg.get(4326)
  let utm50 = @epsg.get(32650)
  let lon = 116.3912
  let lat = 39.9075
  let xy = @crs.transform(wgs84, utm50, lon, lat)
  let back = @crs.transform(utm50, wgs84, xy.0, xy.1)
  assert_true((back.0 - lon).abs() < 1.0e-9)
  assert_true((back.1 - lat).abs() < 1.0e-9)
}

///|
/// 同一个点：自身转换必须恒等。
test "同坐标系恒等" {
  let wgs84 = @epsg.get(4326)
  let xy = @crs.transform(wgs84, wgs84, 116.3912, 39.9075)
  assert_true((xy.0 - 116.3912).abs() < 1.0e-12)
  assert_true((xy.1 - 39.9075).abs() < 1.0e-12)
}

///|
/// 跨基准：英国国家格网 → WGS84 → 格网，闭环误差应小于 1 毫米。
///
/// 这条测试覆盖了 OSGB36 七参数（Helmert）的正反两个方向，
/// 是"基准转换写对了"最直接的证据。
test "OSGB36 跨基准闭环" {
  let bng = @epsg.get(27700)
  let wgs84 = @epsg.get(4326)
  let easting = 651409.903
  let northing = 313177.270
  let lonlat = @crs.transform(bng, wgs84, easting, northing)
  let back = @crs.transform(wgs84, bng, lonlat.0, lonlat.1)
  assert_true((back.0 - easting).abs() < 1.0e-3)
  assert_true((back.1 - northing).abs() < 1.0e-3)
}

///|
/// 跨基准偏移的量级检查：同一个物理点，在 WGS84 与 OSGB36 上的
/// 经纬度应当差百米量级（英国地区约 100 m）。太小说明七参数没生效，
/// 太大说明用错了椭球。
test "OSGB36 与 WGS84 的基准偏移量级" {
  let wgs84 = @epsg.get(4326)
  let osgb = @epsg.get(4277)
  let lon = 1.7179215833
  let lat = 52.6575703056
  let shifted = @crs.transform(wgs84, osgb, lon, lat)
  let d = metres_between(lon, lat, shifted.0, shifted.1)
  assert_true(d > 20.0)
  assert_true(d < 500.0)
  // 反方向应当回到原点附近。容差 1e-7°（约 1 cm）而不是 1e-9°：
  // Helmert 的反解用的是旋转矩阵转置而非严格求逆，残差在
  // "角秒² × 地球半径" 量级（约 1 mm），任何更紧的容差都是自欺。
  let back = @crs.transform(osgb, wgs84, shifted.0, shifted.1)
  assert_true((back.0 - lon).abs() < 1.0e-7)
  assert_true((back.1 - lat).abs() < 1.0e-7)
}

///|
/// 地心坐标系：WGS84 经纬度 → ECEF → 经纬度。
test "地心坐标往返" {
  let wgs84 = @epsg.get(4326)
  let ecef = @epsg.get(4978)
  let xyz = @crs.transform_3d(wgs84, ecef, 116.3912, 39.9075, 50.0)
  // 北京到地心约 6371 km，量级检查
  let r = ((xyz.0 * xyz.0 + xyz.1 * xyz.1 + xyz.2 * xyz.2).sqrt())
  assert_true(r > 6360000.0)
  assert_true(r < 6380000.0)
  let back = @crs.transform_3d(ecef, wgs84, xyz.0, xyz.1, xyz.2)
  assert_true((back.0 - 116.3912).abs() < 1.0e-9)
  assert_true((back.1 - 39.9075).abs() < 1.0e-9)
  assert_true((back.2 - 50.0).abs() < 1.0e-3)
}

///|
/// 比利时 BD72：兰勃特 2SP + 原点纬度在极点（lat_0 = 90°）。
///
/// 这条测试的价值在于覆盖"圆锥投影原点是极点"这种退化情形——
/// 大多数教科书算例都用中纬度原点，极原点分支写错时不易被发现。
test "比利时 Lambert 72" {
  let wgs84 = @epsg.get(4326)
  let bd72 = @epsg.get(31370)
  let lon = 4.36
  let lat = 50.80
  let xy = @crs.transform(wgs84, bd72, lon, lat)
  let back = @crs.transform(bd72, wgs84, xy.0, xy.1)
  assert_true((back.0 - lon).abs() < 1.0e-7)
  assert_true((back.1 - lat).abs() < 1.0e-7)
  // 比利时 Lambert 72 的东坐标约 15 万米、北坐标约 17 万米
  assert_true(xy.0 > 100000.0)
  assert_true(xy.0 < 200000.0)
  assert_true(xy.1 > 100000.0)
  assert_true(xy.1 < 250000.0)
}

///|
/// 本初子午线不是格林尼治时，入参经度必须按"相对该子午线"解释。
///
/// 巴黎子午线在格林尼治以东 2.337229167°。所以"巴黎坐标系上的
/// 经度 0"就是"格林尼治经度 2.337229167"——这条等价关系是本测试的判据。
/// 若实现漏掉 `+pm`，差值会整整少一个 2.34°（约 260 km）。
test "巴黎本初子午线" {
  let paris = @crs.parse("+proj=longlat +ellps=WGS84 +pm=paris")
  let wgs84 = @epsg.get(4326)
  // 巴黎坐标系上的经度 0，就是格林尼治经度 2.337229167°
  let on_greenwich = @crs.transform(paris, wgs84, 0.0, 48.8534)
  assert_true((on_greenwich.0 - 2.337229167).abs() < 1.0e-9)
  assert_true((on_greenwich.1 - 48.8534).abs() < 1.0e-12)
  // 反方向：格林尼治经度 2.337229167° 在巴黎坐标系上应等于 0
  let on_paris = @crs.transform(wgs84, paris, 2.337229167, 48.8534)
  assert_true(on_paris.0.abs() < 1.0e-9)
}

///|
/// 轴序：WKT2 里声明「纬度在前」的坐标系，入参必须按纬、经解释。
test "轴序 LatLon" {
  let text =
    #|GEOGCRS["WGS 84 (lat-lon order)",
    #|    DATUM["World Geodetic System 1984",
    #|        ELLIPSOID["WGS 84",6378137,298.257223563]],
    #|    PRIMEM["Greenwich",0],
    #|    CS[ellipsoidal,2],
    #|        AXIS["geodetic latitude (Lat)",north,ORDER[1]],
    #|        AXIS["geodetic longitude (Lon)",east,ORDER[2]],
    #|        ANGLEUNIT["degree",0.0174532925199433]]
  let latlon = @crs.parse(text)
  let merc = @epsg.get(3857)
  let direct = @crs.transform(latlon, merc, 39.9075, 116.3912)
  let reference = @crs.transform(@epsg.get(4326), merc, 116.3912, 39.9075)
  assert_true((direct.0 - reference.0).abs() < 1.0e-6)
  assert_true((direct.1 - reference.1).abs() < 1.0e-6)
}

///|
/// 单位：NAD27 德州南中（美国测量英尺）必须是英尺。
test "美国测量英尺单位" {
  let wgs84 = @epsg.get(4326)
  let texas = @epsg.get(32040)
  let xy = @crs.transform(wgs84, texas, -96.0, 28.5)
  assert_true((xy.0 - 2963503.91).abs() < 2.0)
  assert_true((xy.1 - 254759.80).abs() < 2.0)
  let back = @crs.transform(texas, wgs84, xy.0, xy.1)
  assert_true((back.0 + 96.0).abs() < 1.0e-7)
  assert_true((back.1 - 28.5).abs() < 1.0e-7)
}

///|
/// 瑞士斜轴墨卡托（Hotine）闭环。这条覆盖 omerc 的 variant B 分支。
test "瑞士 LV95 闭环" {
  let wgs84 = @epsg.get(4326)
  let lv95 = @epsg.get(2056)
  let lon = 7.44
  let lat = 46.95
  let xy = @crs.transform(wgs84, lv95, lon, lat)
  let back = @crs.transform(lv95, wgs84, xy.0, xy.1)
  assert_true((back.0 - lon).abs() < 1.0e-7)
  assert_true((back.1 - lat).abs() < 1.0e-7)
  // LV95 的坐标量级：E ≈ 2.6e6, N ≈ 1.2e6
  assert_true(xy.0 > 2400000.0)
  assert_true(xy.0 < 2800000.0)
}

///|
/// 极区投影：南极与北极两套。
test "极区投影闭环" {
  let wgs84 = @epsg.get(4326)
  let south = @epsg.get(3031)
  let north = @epsg.get(3413)
  let s = @crs.transform(wgs84, south, 0.0, -80.0)
  let sb = @crs.transform(south, wgs84, s.0, s.1)
  assert_true((sb.0 - 0.0).abs() < 1.0e-7)
  assert_true((sb.1 + 80.0).abs() < 1.0e-7)
  let n = @crs.transform(wgs84, north, -45.0, 80.0)
  let nb = @crs.transform(north, wgs84, n.0, n.1)
  assert_true((nb.0 + 45.0).abs() < 1.0e-7)
  assert_true((nb.1 - 80.0).abs() < 1.0e-7)
}

///|
/// 批量转换与单点转换结果必须完全一致（帧复用的正确性）。
test "批量与单点一致" {
  let wgs84 = @epsg.get(4326)
  let utm = @epsg.get(32650)
  let points : Array[(Double, Double)] = [
    (116.3912, 39.9075),
    (117.2, 31.8),
    (113.3, 23.1),
  ]
  let batch = @crs.transform_many(wgs84, utm, points)
  let mut i = 0
  while i < points.length() {
    let single = @crs.transform(wgs84, utm, points[i].0, points[i].1)
    assert_true((single.0 - batch[i].0).abs() < 1.0e-6)
    assert_true((single.1 - batch[i].1).abs() < 1.0e-6)
    i = i + 1
  }
}

///|
/// 格式自动判别：四种写法都应解析成同一个坐标系。
test "四种输入格式" {
  let by_code = @crs.parse("EPSG:4326")
  let by_bare = @crs.parse("4326")
  let by_proj = @crs.parse("+proj=longlat +ellps=WGS84 +datum=WGS84")
  let by_wkt = @crs.parse(
    "GEOGCS[\"WGS 84\",DATUM[\"WGS_1984\",SPHEROID[\"WGS 84\",6378137,298.257223563]],PRIMEM[\"Greenwich\",0],UNIT[\"degree\",0.0174532925199433]]",
  )
  let merc = @epsg.get(3857)
  let a = @crs.transform(by_code, merc, 116.3912, 39.9075)
  let b = @crs.transform(by_bare, merc, 116.3912, 39.9075)
  let c = @crs.transform(by_proj, merc, 116.3912, 39.9075)
  let d = @crs.transform(by_wkt, merc, 116.3912, 39.9075)
  assert_true((a.0 - b.0).abs() < 1.0e-9)
  assert_true((a.0 - c.0).abs() < 1.0e-9)
  // WKT 里的角度单位因子写了 16 位有效数字（0.0174532925199433），
  // 与精确的 π/180 差 5e-18，换算到 1.3e7 米的横坐标上就是 2e-9 米。
  // 因此与 WKT 源的比对容差放到微米级。
  assert_true((a.0 - d.0).abs() < 1.0e-6)
}

///|
/// `+init=epsg:NNNN` 引用注册表。
test "PROJ init 引用" {
  let crs = @crs.parse("+init=epsg:32650")
  assert_true(crs.name() == "WGS 84 / UTM zone 50N")
}

///|
/// 描述输出应包含关键信息。
test "describe 输出" {
  let text = @crs.describe(@epsg.get(32650))
  assert_true(text.contains("WGS 84 / UTM zone 50N"))
  assert_true(text.contains("EPSG:32650"))
  assert_true(text.contains("Transverse Mercator"))
}

///|
/// 跨格式：PROJ 串 → WKT2 → 再解析，投影方法必须保持一致。
test "PROJ 转 WKT 再转回" {
  let from_proj = @crs.parse("+proj=lcc +lat_1=25 +lat_2=47 +lat_0=0 +lon_0=105 +x_0=0 +y_0=0 +ellps=GRS80")
  let wkt_text = @wkt.to_wkt2(from_proj)
  let reparsed = @crs.parse(wkt_text)
  match from_proj {
    Projected(a) =>
      match reparsed {
        Projected(b) => {
          assert_true(a.method_code == b.method_code)
          assert_true(a.method_code == 9802)
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}
