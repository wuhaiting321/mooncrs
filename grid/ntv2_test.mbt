// NTv2 解析与插值的测试。
//
// 全部用**内存里合成**的 .gsb：仓库里不塞任何第三方网格数据（版权与体积
// 都不合适），但"合成"不等于"随便造"——被测的解析器读的是真正的二进制
// 布局（文件头 11 条记录、子文件头 11 条记录、每节点 4 个 float32），
// 任何一个字段偏移错了都会立刻失败。
//
// 节点值由解析函数给出（`field(lon, lat)`），于是"正确结果"有闭式表达：
// 双线性插值对双线性场是精确的，所以可以断言到 1.0e-6 角秒，而不是
// 只断言"看起来差不多"。

///|
/// 子网格规格（度）。
struct Spec {
  name : String
  parent : String
  south : Double
  west : Double
  north : Double
  east : Double
  lat_inc : Double
  lon_inc : Double
}

///|
/// 写 8 字节文本域（不足补空格）。
fn push_text(buf : Array[Byte], s : String) -> Unit {
  // 注意：String::to_bytes 给的是 UTF-16 码元字节，不是 UTF-8，
  // 直接当 ASCII 写会变成 "N\0U\0M\0"。这里按字符取码点。
  let mut i = 0
  while i < 8 {
    let code = match s.get_char(i) {
      Some(c) => c.to_int()
      None => 0x20
    }
    buf.push(code.to_byte())
    i = i + 1
  }
}

///|
/// 写小端 int32。
fn push_i32(buf : Array[Byte], v : Int) -> Unit {
  let u = v.reinterpret_as_uint()
  buf.push(u.to_byte())
  buf.push((u >> 8).to_byte())
  buf.push((u >> 16).to_byte())
  buf.push((u >> 24).to_byte())
  // 记录的数值域固定 8 字节：int32 占前 4 字节，后 4 字节填 0。
  // 少了这 4 个 0，后面所有记录会整体错位 4 字节。
  buf.push(0)
  buf.push(0)
  buf.push(0)
  buf.push(0)
}

///|
/// 写小端 float64。
fn push_f64(buf : Array[Byte], v : Double) -> Unit {
  let u = v.reinterpret_as_uint64()
  let mut i = 0
  while i < 8 {
    buf.push((u >> (i * 8)).to_byte())
    i = i + 1
  }
}

///|
/// 写小端 float32。
fn push_f32(buf : Array[Byte], v : Float) -> Unit {
  let bs = v.to_le_bytes()
  let mut i = 0
  while i < bs.length() {
    match bs.get(i) {
      Some(b) => buf.push(b)
      None => ()
    }
    i = i + 1
  }
}

///|
/// 合成一个 .gsb。
///
/// 后四个参数是**故意做坏**用的：标签写错、计数写错、截断文件，
/// 用来验证"坏文件必须报错而不是算出个东西"。
fn build_gsb(
  specs : Array[Spec],
  field : (Double, Double) -> (Float, Float),
  gs_type~ : String = "SECONDS ",
  orec_label~ : String = "NUM_OREC",
  count_delta~ : Int = 0,
  cut~ : Int = 0,
  east_positive~ : Bool = false,
) -> Bytes {
  let buf : Array[Byte] = []
  push_text(buf, orec_label)
  push_i32(buf, 11)
  push_text(buf, "NUM_SREC")
  push_i32(buf, 11)
  push_text(buf, "NUM_FILE")
  push_i32(buf, specs.length())
  push_text(buf, "GS_TYPE")
  push_text(buf, gs_type)
  push_text(buf, "VERSION")
  push_text(buf, "NTv2.0")
  push_text(buf, "SYSTEM_F")
  push_text(buf, "TESTF")
  push_text(buf, "SYSTEM_T")
  push_text(buf, "TESTT")
  push_text(buf, "MAJOR_F")
  push_f64(buf, 6378206.4)
  push_text(buf, "MINOR_F")
  push_f64(buf, 6356583.8)
  push_text(buf, "MAJOR_T")
  push_f64(buf, 6378137.0)
  push_text(buf, "MINOR_T")
  push_f64(buf, 6356752.314140356)
  for s in specs {
    let nrows = ((s.north - s.south) / s.lat_inc + 0.5).to_int() + 1
    let ncols = ((s.east - s.west) / s.lon_inc + 0.5).to_int() + 1
    push_text(buf, "SUB_NAME")
    push_text(buf, s.name)
    push_text(buf, "PARENT")
    push_text(buf, s.parent)
    push_text(buf, "CREATED")
    push_text(buf, "95-06-30")
    push_text(buf, "UPDATED")
    push_text(buf, "95-07-05")
    push_text(buf, "S_LAT")
    push_f64(buf, s.south * 3600.0)
    push_text(buf, "N_LAT")
    push_f64(buf, s.north * 3600.0)
    // 规范默认正西：东边界写成 -east
    push_text(buf, "E_LONG")
    push_f64(buf, if east_positive { s.east * 3600.0 } else { -s.east * 3600.0 })
    push_text(buf, "W_LONG")
    push_f64(buf, if east_positive { s.west * 3600.0 } else { -s.west * 3600.0 })
    push_text(buf, "LAT_INC")
    push_f64(buf, s.lat_inc * 3600.0)
    push_text(buf, "LONG_INC")
    push_f64(buf, s.lon_inc * 3600.0)
    push_text(buf, "GS_COUNT")
    push_i32(buf, nrows * ncols + count_delta)
    // 节点：从东南角起，先向西（列），再向北（行）
    let mut r = 0
    while r < nrows {
      let lat = s.south + r.to_double() * s.lat_inc
      let mut c = 0
      while c < ncols {
        let lon = s.east - c.to_double() * s.lon_inc
        let v = field(lon, lat)
        push_f32(buf, v.0)
        push_f32(buf, v.1)
        push_f32(buf, 0.0F)
        push_f32(buf, 0.0F)
        c = c + 1
      }
      r = r + 1
    }
  }
  if cut > 0 && cut < buf.length() {
    buf.truncate(cut)
  }
  Bytes::from_array(buf)
}

///|
/// 测试用的双线性场：纬改正与经改正都是 lon/lat 的线性函数。
///
/// 量级刻意贴近真实：NTv2 的改正量通常在 1 角秒上下。这一点很关键——
/// 若把系数放大到几百角秒，float32 的量化误差本身就有 1e-5 角秒，
/// 那时"插值误差 < 1e-6 角秒"测的其实是存储精度，不是插值算法。
fn linear_field(lon : Double, lat : Double) -> (Float, Float) {
  let dlat = 0.5 + 0.002 * (lon + 115.0) + 0.003 * (lat - 35.0)
  let dlon = -0.25 + 0.0015 * (lon + 115.0) - 0.002 * (lat - 35.0)
  (Float::from_double(dlat), Float::from_double(dlon))
}

///|
/// 一个 10° × 10° 的子网格，格距 0.25°（41 × 41 节点）。
fn small_spec() -> Spec {
  {
    name: "TESTSUB",
    parent: "NONE",
    south: 30.0,
    west: -120.0,
    north: 40.0,
    east: -110.0,
    lat_inc: 0.25,
    lon_inc: 0.25,
  }
}

///|
/// 解析基本字段：文件头、子网格范围、节点数、经度约定。
test "解析文件头与子网格范围" {
  let grid = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field), name="test.gsb")
  assert_eq(grid.len(), 1)
  assert_eq(grid.version, "NTv2.0")
  assert_eq(grid.from_system, "TESTF")
  assert_eq(grid.to_system, "TESTT")
  assert_true((grid.from_ellipsoid.0 - 6378206.4).abs() < 1.0e-6)
  assert_eq(grid.lon_convention, "west-positive")
  let s = grid.subs[0]
  assert_eq(s.name, "TESTSUB")
  assert_true(s.is_root())
  assert_eq(s.nrows, 41)
  assert_eq(s.ncols, 41)
  // 文件里是正西角秒，解析后统一成东经为正的度
  assert_true((s.south - 30.0).abs() < 1.0e-12)
  assert_true((s.north - 40.0).abs() < 1.0e-12)
  assert_true((s.west + 120.0).abs() < 1.0e-12)
  assert_true((s.east + 110.0).abs() < 1.0e-12)
}

///|
/// B2：节点处的改正量必须与写入值逐位一致（误差 < 1.0e-9 角秒）。
test "节点处读回误差小于 1.0e-9 角秒" {
  let grid = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field))
  let mut r = 0
  while r < 41 {
    let lat = 30.0 + r.to_double() * 0.25
    let mut c = 0
    while c < 41 {
      let lon = -110.0 - c.to_double() * 0.25
      let got = match grid.forward(lon, lat) {
        Some(g) => g
        None => {
          assert_true(false)
          continue
        }
      }
      let want = linear_field(lon, lat)
      // 文件里 dlon 是正西，读出来要反号
      let got_lat = got.dlat * 3600.0
      let got_lon = -got.dlon * 3600.0
      assert_true((got_lat - want.0.to_double()).abs() < 1.0e-9)
      assert_true((got_lon - want.1.to_double()).abs() < 1.0e-9)
      c = c + 1
    }
    r = r + 1
  }
}

///|
/// B3：节点之间（含格子正中、四分之一处）误差 < 1.0e-6 角秒。
///
/// 双线性插值对线性场是精确的，所以这里几乎不该有误差；阈值放到 1.0e-6
/// 是为了容忍 float32 存储带来的舍入。
test "节点之间插值误差小于 1.0e-6 角秒" {
  let grid = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field))
  let fracs : Array[Double] = [0.1, 0.25, 0.5, 0.75, 0.9]
  for fr in fracs {
    for fc in fracs {
      let lon = -119.5 + fc * 0.25
      let lat = 33.5 + fr * 0.25
      let got = match grid.forward(lon, lat) {
        Some(g) => g
        None => {
          assert_true(false)
          continue
        }
      }
      let want = linear_field(lon, lat)
      assert_true((got.dlat * 3600.0 - want.0.to_double()).abs() < 1.0e-6)
      assert_true((-got.dlon * 3600.0 - want.1.to_double()).abs() < 1.0e-6)
    }
  }
}

///|
/// B4：范围外返回 None，不抛异常、不外推。
///
/// 四角在边界上属于范围内（含边界），四边外 0.001° 必须拒答。
test "范围外返回空而不外推" {
  let grid = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field))
  // 四角：有效
  let corners : Array[(Double, Double)] = [
    (-120.0, 30.0),
    (-110.0, 30.0),
    (-120.0, 40.0),
    (-110.0, 40.0),
  ]
  for corner in corners {
    assert_true(grid.forward(corner.0, corner.1) is Some(_))
  }
  // 四边外 0.001°
  let out : Array[(Double, Double)] = [
    (-120.001, 35.0), (-109.999, 35.0), (-115.0, 29.999), (-115.0, 40.001),
  ]
  for p in out {
    assert_true(grid.forward(p.0, p.1) is None)
  }
  // 远处：不只是"差一点"
  assert_true(grid.forward(0.0, 0.0) is None)
}

///|
/// 正东经约定的文件（部分欧洲文件如此）：靠 east > west 自洽条件识别。
test "识别正东经约定的文件" {
  let grid = @grid.Ntv2Grid::parse(
    build_gsb([small_spec()], linear_field, east_positive=true),
  )
  assert_eq(grid.lon_convention, "east-positive")
  let s = grid.subs[0]
  assert_true((s.west + 120.0).abs() < 1.0e-12)
  assert_true((s.east + 110.0).abs() < 1.0e-12)
  assert_true(grid.forward(-115.0, 35.0) is Some(_))
}

///|
/// 反解：对同一场做正反两次，回到原点应在 1.0e-9 度内。
///
/// 反解是不动点迭代，不是解析式，所以这条测试同时验证了收敛判据。
test "网格正反解闭环" {
  let grid = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field))
  let pts : Array[(Double, Double)] = [
    (-115.0, 35.0), (-119.75, 30.25), (-110.25, 39.75), (-113.3, 36.6),
  ]
  for p in pts {
    let fwd = match grid.forward(p.0, p.1) {
      Some(g) => g
      None => {
        assert_true(false)
        continue
      }
    }
    let moved = (p.0 + fwd.dlon, p.1 + fwd.dlat)
    let back = match grid.unshift(moved.0, moved.1) {
      Some(g) => g
      None => {
        assert_true(false)
        continue
      }
    }
    let restored = (moved.0 + back.dlon, moved.1 + back.dlat)
    assert_true((restored.0 - p.0).abs() < 1.0e-9)
    assert_true((restored.1 - p.1).abs() < 1.0e-9)
    // 迭代次数要落在合理区间：超过 6 次说明判据太松或场太陡
    assert_true(back.iterations >= 1 && back.iterations <= 6)
  }
}

///|
/// 反解在网格外必须返回 None，不能"沿着边缘继续迭代"。
test "反解在范围外返回空" {
  let grid = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field))
  assert_true(grid.unshift(-125.0, 35.0) is None)
  assert_true(grid.unshift(-115.0, 45.0) is None)
}

///|
/// 多子网格：重叠时取面积最小的那个。
///
/// NTv2 的子网格就是局部加密，取大的等于把加密数据浪费掉。
test "重叠子网格取面积最小的" {
  let coarse : Spec = {
    name: "COARSE",
    parent: "NONE",
    south: 30.0,
    west: -120.0,
    north: 40.0,
    east: -110.0,
    lat_inc: 1.0,
    lon_inc: 1.0,
  }
  let fine : Spec = {
    name: "FINE",
    parent: "COARSE",
    south: 34.0,
    west: -116.0,
    north: 36.0,
    east: -114.0,
    lat_inc: 0.25,
    lon_inc: 0.25,
  }
  let grid = @grid.Ntv2Grid::parse(build_gsb([coarse, fine], linear_field))
  assert_eq(grid.len(), 2)
  match grid.find(-115.0, 35.0) {
    Some(s) => assert_eq(s.name, "FINE")
    None => assert_true(false)
  }
  // 加密区之外仍在母网格内
  match grid.find(-118.0, 38.0) {
    Some(s) => assert_eq(s.name, "COARSE")
    None => assert_true(false)
  }
  // 完全在外
  assert_true(grid.find(-100.0, 38.0) is None)
}

///|
/// B6：坏文件必须报错，而不是崩、也不是算出个数。
test "坏文件一律报错" {
  // 1) 不是 NTv2：随机二进制
  let junk : Array[Byte] = []
  let mut i = 0
  while i < 300 {
    junk.push((0xAB).to_byte())
    i = i + 1
  }
  let junk_bytes = Bytes::from_array(junk)
  let mut caught = false
  try {
    let _ = @grid.Ntv2Grid::parse(junk_bytes)
  } catch {
    _ => caught = true
  }
  assert_true(caught)

  // 2) 标签错位
  caught = false
  try {
    let _ = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field, orec_label="NUM_OREX"))
  } catch {
    e => {
      caught = true
      assert_true(e.message().contains("NUM_OREX") || e.message().contains("标签"))
    }
  }
  assert_true(caught)

  // 3) 节点数对不上（GS_COUNT 被改）
  caught = false
  try {
    let _ = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field, count_delta=1))
  } catch {
    e => {
      caught = true
      assert_true(e.message().contains("GS_COUNT"))
    }
  }
  assert_true(caught)

  // 4) 截断：只留文件头 + 一个子文件头
  caught = false
  try {
    let _ = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field, cut=400))
  } catch {
    e => {
      caught = true
      assert_true(e.message().contains("截断") || e.message().contains("越过文件末尾"))
    }
  }
  assert_true(caught)

  // 5) GS_TYPE 不是 SECONDS
  caught = false
  try {
    let _ = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field, gs_type="MINUTES "))
  } catch {
    e => {
      caught = true
      assert_true(e.message().contains("SECONDS"))
    }
  }
  assert_true(caught)
}

///|
/// 空字节与超短输入：报错信息要说清"太短"，不能是越界 panic。
test "空输入给出可读错误" {
  let none : Array[Byte] = []
  let empty = Bytes::from_array(none)
  let mut caught = false
  try {
    let _ = @grid.Ntv2Grid::parse(empty)
  } catch {
    e => {
      caught = true
      assert_true(e.message().contains("太短"))
    }
  }
  assert_true(caught)
}

///|
/// 网格集合：按标识取用、保持确定性顺序。
test "网格集合按标识索引" {
  let set = @grid.GridSet::empty()
  assert_true(set.is_empty())
  let grid = @grid.Ntv2Grid::parse(build_gsb([small_spec()], linear_field), name="a.gsb")
  set.add("COARSE", grid)
  assert_true(!set.is_empty())
  assert_true(set.contains("COARSE"))
  assert_true(!set.contains("OSTN15"))
  assert_true(set.ids().length() == 1 && set.ids()[0] == "COARSE")
  match set.get("COARSE") {
    Some(g) => assert_eq(g.name, "a.gsb")
    None => assert_true(false)
  }
}
