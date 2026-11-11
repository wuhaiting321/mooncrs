// 大地几何与 Helmert 变换测试。
//
// 这一层的判据最干净：椭球上的几个特殊点在空间直角坐标里有**精确**值
// （赤道、极点、球心），不需要任何外部参考数据就能断言。

///|
let pi_d : Double = 3.141592653589793

///|
/// 赤道上经度 0、大地高 0 的点，其地心坐标应为 (a, 0, 0)。
test "赤道点的地心坐标" {
  let a = 6378137.0
  let e2 = @types.wgs84.e2()
  let xyz = @crs.geodetic_to_geocentric(a, e2, 0.0, 0.0, 0.0)
  assert_true((xyz.0 - a).abs() < 1.0e-6)
  assert_true(xyz.1.abs() < 1.0e-6)
  assert_true(xyz.2.abs() < 1.0e-6)
}

///|
/// 北极点的地心坐标为 (0, 0, b)。
test "极点的地心坐标" {
  let a = 6378137.0
  let e2 = @types.wgs84.e2()
  let b = @types.wgs84.semi_minor()
  let xyz = @crs.geodetic_to_geocentric(a, e2, 0.0, pi_d / 2.0, 0.0)
  assert_true(xyz.0.abs() < 1.0e-6)
  assert_true(xyz.1.abs() < 1.0e-6)
  assert_true((xyz.2 - b).abs() < 1.0e-6)
}

///|
/// 地心 → 大地 → 地心必须闭合。
test "地心坐标往返" {
  let a = 6378137.0
  let e2 = @types.wgs84.e2()
  let lon = 1.0
  let lat = 0.6
  let h = 1234.5
  let xyz = @crs.geodetic_to_geocentric(a, e2, lon, lat, h)
  let back = @crs.geocentric_to_geodetic(a, e2, xyz.0, xyz.1, xyz.2)
  assert_true((back.0 - lon).abs() < 1.0e-12)
  assert_true((back.1 - lat).abs() < 1.0e-12)
  assert_true((back.2 - h).abs() < 1.0e-6)
}

///|
/// Helmert 正反变换应互为逆，残差在亚毫米级。
///
/// 容差取 1 毫米而不是机器精度：反解用的是旋转矩阵转置（`M⁻¹ ≈ Mᵀ`），
/// 残差量级是 θ²·R。这里的 θ 最大 0.84 角秒 ≈ 4e-6 rad，
/// 4e-6² × 6.4e6 ≈ 1e-4 m。任何要求更紧的断言都等于要求"算错"。
test "Helmert 正反互逆" {
  let h = @types.Helmert::new(446.448, -125.157, 542.06, 0.1502, 0.247, 0.8421, -20.4894)
  let p = (3839000.0, -140000.0, 5080000.0)
  let fwd = @crs.helmert_forward(h, p.0, p.1, p.2)
  let back = @crs.helmert_inverse(h, fwd.0, fwd.1, fwd.2)
  assert_true((back.0 - p.0).abs() < 1.0e-3)
  assert_true((back.1 - p.1).abs() < 1.0e-3)
  assert_true((back.2 - p.2).abs() < 1.0e-3)
}

///|
/// 两种旋转约定的差别：Position Vector 与 Coordinate Frame 的旋转方向相反。
///
/// 用同一组参数分别构造两种约定，纯旋转（平移与尺度置零）下的结果
/// 应当关于原点镜像——即 X、Y、Z 的偏移量符号相反、量级相同。
/// 这条测试专门守住"把 9606 写成 9607"这类错误：数值上仍然"像那么回事"，
/// 但方向整体反了，误差是两倍旋转量。
test "两种旋转约定方向相反" {
  let pv = @types.Helmert::new(0.0, 0.0, 0.0, 0.0, 0.0, 10.0, 0.0)
  let cf = @types.Helmert::new(
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    10.0,
    0.0,
    convention=@types.CoordinateFrame,
  )
  let p = (5000000.0, 1000000.0, 4000000.0)
  let a = @crs.helmert_forward(pv, p.0, p.1, p.2)
  let b = @crs.helmert_forward(cf, p.0, p.1, p.2)
  // X 分量受 rz 影响：两边的偏移符号必须相反
  let da = a.0 - p.0
  let db = b.0 - p.0
  assert_true(da * db < 0.0)
  assert_true((da.abs() - db.abs()).abs() < 1.0e-9)
}

///|
/// 单位变换应完全无副作用。
test "单位 Helmert" {
  let h = @types.helmert_identity
  let p = (1234567.0, 2345678.0, 3456789.0)
  let r = @crs.helmert_forward(h, p.0, p.1, p.2)
  assert_true(r.0 == p.0)
  assert_true(r.1 == p.1)
  assert_true(r.2 == p.2)
}
