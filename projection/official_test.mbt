// 投影层回归测试。
//
// 判据优先级：**EPSG 官方算例 > 往返一致性 > 自洽性**。
//
// 只有第一类能证明"公式写对了"；往返一致性只能证明"正反算互逆"，
// 一个整体缩放错的实现照样能完美往返。所以每个方法都尽量配一个
// 官方算例，实在没有公开算例的（如 LAEA 的特定区域）才退到往返。

///|
/// EPSG Guidance Note 7-2 的横轴墨卡托算例：
/// OSGB36 / British National Grid（EPSG:27700）。
test "EPSG 9807: British National Grid 官方算例" {
  let proj = @projection.Projection::transverse_mercator(
    @types.airy1830,
    @projection.deg2rad(-2.0),
    lat0=@projection.deg2rad(49.0),
    k0=0.9996012717,
    fe=400000.0,
    fnorth=-100000.0,
  )
  let lon = @projection.deg2rad(1.0 + 43.0 / 60.0 + 4.5177 / 3600.0)
  let lat = @projection.deg2rad(52.0 + 39.0 / 60.0 + 27.2531 / 3600.0)
  let xy = proj.forward(lon, lat)
  // EPSG 公布值：E 651409.903, N 313177.270（米）
  assert_true((xy.0 - 651409.903).abs() < 0.01)
  assert_true((xy.1 - 313177.270).abs() < 0.01)
}

///|
/// 同一算例的反算：平面坐标回到经纬度。
test "EPSG 9807: British National Grid 反算" {
  let proj = @projection.Projection::transverse_mercator(
    @types.airy1830,
    @projection.deg2rad(-2.0),
    lat0=@projection.deg2rad(49.0),
    k0=0.9996012717,
    fe=400000.0,
    fnorth=-100000.0,
  )
  let lonlat = proj.inverse(651409.903, 313177.270)
  let lon_deg = @projection.rad2deg(lonlat.0)
  let lat_deg = @projection.rad2deg(lonlat.1)
  assert_true((lon_deg - 1.7179215833).abs() < 1.0e-7)
  assert_true((lat_deg - 52.6575703056).abs() < 1.0e-7)
}

///|
/// EPSG Guidance Note 7-2 的兰勃特（2SP）算例：
/// NAD27 / Texas South Central（EPSG:32040，单位美国测量英尺）。
test "EPSG 9802: Texas South Central 官方算例" {
  let us_ft = @types.us_survey_foot.factor
  let proj = @projection.Projection::lcc_2sp(
    @types.clarke1866,
    @projection.deg2rad(-99.0),
    @projection.deg2rad(27.0 + 50.0 / 60.0),
    @projection.deg2rad(28.0 + 23.0 / 60.0),
    @projection.deg2rad(30.0 + 17.0 / 60.0),
    fe=2000000.0 * us_ft,
    fnorth=0.0,
  )
  let xy = proj.forward(@projection.deg2rad(-96.0), @projection.deg2rad(28.5))
  let easting_ft = xy.0 / us_ft
  let northing_ft = xy.1 / us_ft
  // EPSG 公布值：E 2963503.91, N 254759.80（美国测量英尺）
  assert_true((easting_ft - 2963503.91).abs() < 0.02)
  assert_true((northing_ft - 254759.80).abs() < 0.02)
}

///|
/// Web Mercator 的定义是"球面公式套 WGS84 长半轴"，这里用显式公式
/// 独立复算一遍：x = a·λ，y = a·ln(tan(π/4 + φ/2))。
/// 这条测试的意义是防止有人"顺手"把它改成椭球墨卡托——那会让所有
/// 在线地图瓦片错位约 20 km。
test "EPSG 1024: Web Mercator 球面公式" {
  let proj = @projection.Projection::web_mercator(@types.wgs84)
  let lon = @projection.deg2rad(116.4)
  let lat = @projection.deg2rad(39.9)
  let xy = proj.forward(lon, lat)
  let a = 6378137.0
  let expected_x = a * lon
  let expected_y = a * @math.ln(@math.tan(@projection.pi / 4.0 + lat / 2.0))
  assert_true((xy.0 - expected_x).abs() < 1.0e-6)
  assert_true((xy.1 - expected_y).abs() < 1.0e-6)
}

///|
/// 横轴墨卡托在中央经线上应严格成立 x = 假东（经度方向无畸变）。
test "EPSG 9807: 中央经线上横坐标等于假东" {
  let proj = @projection.Projection::transverse_mercator(
    @types.wgs84,
    @projection.deg2rad(117.0),
    k0=0.9996,
    fe=500000.0,
  )
  let xy = proj.forward(@projection.deg2rad(117.0), @projection.deg2rad(31.2))
  assert_true((xy.0 - 500000.0).abs() < 1.0e-6)
}

///|
/// 各方法的往返一致性。容差按"往返后经纬度偏差"衡量，取 1e-7 度
/// （约 1 厘米）——比任何实际测量的精度都严格。
///
/// 每个方法都配了一个落在其有效范围内的测试点：极射赤面只对极区有意义，
/// 圆锥投影对极点退化，用同一个点测所有方法只会得到一堆 NaN 假阴性。
test "十种投影方法往返一致" {
  let cases : Array[(@projection.Projection, Double, Double)] = [
    (
      @projection.Projection::transverse_mercator(@types.wgs84, @projection.deg2rad(117.0), k0=0.9996, fe=500000.0),
      116.3912,
      39.9075,
    ),
    (@projection.Projection::utm(@types.wgs84, 50), 116.3912, 39.9075),
    (@projection.Projection::utm(@types.wgs84, 50, south=true), 116.3912, -33.8688),
    (@projection.Projection::web_mercator(@types.wgs84), 116.3912, 39.9075),
    (@projection.Projection::mercator_1sp(@types.wgs84, @projection.deg2rad(0.0), k0=1.0), 116.3912, 39.9075),
    (@projection.Projection::mercator_2sp(@types.wgs84, @projection.deg2rad(0.0), @projection.deg2rad(42.0)), 116.3912, 39.9075),
    (
      @projection.Projection::lcc_2sp(
        @types.grs80,
        @projection.deg2rad(3.0),
        @projection.deg2rad(46.5),
        @projection.deg2rad(44.0),
        @projection.deg2rad(49.0),
        fe=700000.0,
        fnorth=6600000.0,
      ),
      2.3522,
      48.8566,
    ),
    (
      @projection.Projection::lcc_1sp(@types.grs80, @projection.deg2rad(117.0), @projection.deg2rad(39.5), k0=1.0),
      116.3912,
      39.9075,
    ),
    (
      @projection.Projection::albers(
        @types.grs80,
        @projection.deg2rad(105.0),
        @projection.deg2rad(0.0),
        @projection.deg2rad(25.0),
        @projection.deg2rad(47.0),
      ),
      116.3912,
      39.9075,
    ),
    (
      @projection.Projection::laea(
        @types.grs80,
        @projection.deg2rad(10.0),
        @projection.deg2rad(52.0),
        fe=4321000.0,
        fnorth=3210000.0,
      ),
      10.0,
      52.0,
    ),
    (@projection.Projection::polar_stereographic_b(@types.wgs84, @projection.deg2rad(70.0), @projection.deg2rad(-45.0)), -45.0, 80.0),
    (
      @projection.Projection::polar_stereographic_a(
        @types.wgs84,
        @projection.deg2rad(90.0),
        @projection.deg2rad(0.0),
        k0=0.994,
        fe=2000000.0,
        fnorth=2000000.0,
      ),
      10.0,
      85.0,
    ),
    (@projection.Projection::cassini(@types.krassowsky1940, @projection.deg2rad(117.0), @projection.deg2rad(0.0)), 116.3912, 39.9075),
    (
      @projection.Projection::hotine_oblique(
        @types.bessel1841,
        @projection.deg2rad(46.95240555555556),
        @projection.deg2rad(7.439583333333333),
        @projection.deg2rad(90.0),
        @projection.deg2rad(90.0),
        1.0,
        fe=2600000.0,
        fnorth=1200000.0,
      ),
      7.0,
      47.0,
    ),
  ]
  for c in cases {
    let proj = c.0
    let lon = c.1
    let lat = c.2
    let xy = proj.forward(@projection.deg2rad(lon), @projection.deg2rad(lat))
    let back = proj.inverse(xy.0, xy.1)
    let dlon = (@projection.rad2deg(back.0) - lon).abs()
    let dlat = (@projection.rad2deg(back.1) - lat).abs()
    assert_true(dlon < 1.0e-7)
    assert_true(dlat < 1.0e-7)
  }
}

///|
/// 经度归一化：跨 ±180° 不应产生跳变。
test "经度归一化跨 180 度连续" {
  let proj = @projection.Projection::mercator_1sp(@types.wgs84, 0.0, k0=1.0)
  let west = proj.forward(@projection.deg2rad(179.5), @projection.deg2rad(10.0))
  let east = proj.forward(@projection.deg2rad(-179.5), @projection.deg2rad(10.0))
  // 两侧应关于中央经线对称，而不是相差 359 度。
  assert_true((west.0.abs() - east.0.abs()).abs() < 1.0e-6)
}

///|
/// 非法输入必须报错，而不是给出 NaN。
test "非法纬度报错" {
  let proj = @projection.Projection::mercator_1sp(@types.wgs84, 0.0, k0=1.0)
  let ok = try {
    let _ = proj.forward(@projection.deg2rad(0.0), @projection.deg2rad(95.0))
    false
  } catch {
    _ => true
  }
  assert_true(ok)
}

///|
/// 尺度因子非正时应拒绝构造。
test "尺度因子校验" {
  let ok = try {
    let _ = @projection.Projection::mercator_1sp(@types.wgs84, 0.0, k0=0.0)
    false
  } catch {
    _ => true
  }
  assert_true(ok)
}

///|
/// 子午线弧长与反解应互逆（Snyder 八阶级数的精度检查）。
test "子午线弧长反解互逆" {
  let a = 6378137.0
  let e2 = @types.wgs84.e2()
  for lat_deg in [0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 89.0] {
    let m = @projection.meridian_arc(a, e2, @projection.deg2rad(lat_deg))
    let back = @projection.latitude_from_meridian_arc(a, e2, m)
    assert_true((@projection.rad2deg(back) - lat_deg).abs() < 1.0e-9)
  }
}

///|
/// 等积投影的核心性质：面积比等于 1。用 Albers 检验——
/// 在小区域内取四个角点，比较平面面积与椭球面面积。
test "Albers 等积性质" {
  let proj = @projection.Projection::albers(
    @types.wgs84,
    @projection.deg2rad(105.0),
    @projection.deg2rad(0.0),
    @projection.deg2rad(25.0),
    @projection.deg2rad(47.0),
  )
  let lon0 = @projection.deg2rad(110.0)
  let lat0 = @projection.deg2rad(35.0)
  // 步长取 1e-5 弧度：太小会引入相减抵消误差，太大则二阶截断误差显现。
  let d = 1.0e-5
  let p1 = proj.forward(lon0, lat0)
  let p2 = proj.forward(lon0 + d, lat0)
  let p4 = proj.forward(lon0, lat0 + d)
  // 必须用雅可比行列式（平行四边形面积），不能用"宽×高"：
  // 阿尔伯斯的经线是收敛的，∂x/∂φ 不为零，宽×高会漏掉交叉项。
  let ax = p2.0 - p1.0
  let ay = p2.1 - p1.1
  let bx = p4.0 - p1.0
  let by = p4.1 - p1.1
  let planar = (ax * by - bx * ay).abs()
  // 椭球面积元素：dA = a²(1-e²)cosφ dφ dλ / (1-e²sin²φ)²
  let a = 6378137.0
  let e2 = @types.wgs84.e2()
  let s = @math.sin(lat0)
  let w = 1.0 - e2 * s * s
  let sphere = a * a * (1.0 - e2) * @math.cos(lat0) * d * d / (w * w)
  // 等积要求两者相差 < 0.001%（残差主要来自差分本身，不是投影误差）
  assert_true(((planar - sphere) / sphere).abs() < 1.0e-5)
}
