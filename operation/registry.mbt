// 坐标运算注册表。
//
// 每条记录回答四个问题：用哪条运算、在哪儿成立、精度多少、参数从哪来。
// 没有这四样，坐标转换就退化成"算得出来但不敢用"。
//
// 收录原则：
// 1. **只收有出处的参数集**。`authority` 写清来源，`note` 写清限制。
// 2. **`EPSG:xxxx` 只用于编号确凿的 registry 运算**；按公开参数自建、
//    未主张 EPSG 编号的记录一律用 `LOCAL:` 前缀。宁可标 LOCAL，
//    也不给一个查不到的编号。
// 3. **不收"看起来更好"的凑数条目**。少一条不影响可用性，错一条会误导人。
//
// 当前覆盖 14 个基准：WGS84 / WGS72 / NAD83 / NAD27 / ETRS89 / CGCS2000 /
// OSGB36 / BD72 / CH1903 / DHDN / TM65 / GDA94 / RGF93 / ED50。
// 没覆盖的基准（如 Xian 1980、Beijing 1954）在注册表里查不到运算，
// 转换会显式报错并提示缺什么——这是刻意保留的"不支持"样本。

///|
/// 全部运算。反向运算不单独登记，由 `resolve` 按需派生。
pub fn all() -> Array[CoordinateOperation] raise @types.CrsError {
  let ops : Array[CoordinateOperation] = []

  // ── 视为重合的基准对 ────────────────────────────────────────────
  // 这些不是"没有运算"，而是"有一条精度已知的恒等运算"。
  ops.push(
    coincident(
      "LOCAL:WGS84_ETRS89",
      "WGS 84 ↔ ETRS89（视为重合）",
      "WGS84",
      "ETRS89",
      BoundingBox::world(),
      0.05,
      "EPSG Guidance Note 7-2",
      "ITRS 与 ETRS89 在 1989.0 历元重合，此后差异随欧亚板块运动增长，欧洲范围内仍 < 0.1 m",
    ),
  )
  ops.push(
    coincident(
      "LOCAL:ETRS89_RGF93",
      "ETRS89 ↔ RGF93（同一实现）",
      "ETRS89",
      "RGF93",
      france(),
      0.01,
      "IGN France",
      "RGF93 是 ETRS89 在法国的实现，两者无参数差异",
    ),
  )
  ops.push(
    coincident(
      "LOCAL:WGS84_RGF93",
      "WGS 84 ↔ RGF93（视为重合）",
      "WGS84",
      "RGF93",
      france(),
      0.05,
      "IGN France",
      "经 ETRS89 转达；法国本土差异 < 0.1 m",
    ),
  )
  ops.push(
    coincident(
      "LOCAL:CGCS2000_WGS84",
      "CGCS2000 ↔ WGS 84（视为重合）",
      "CGCS2000",
      "WGS84",
      china(),
      0.05,
      "中国国家测绘局 CGCS2000 说明",
      "CGCS2000 与 WGS84 在厘米级一致，无公开的官方转换参数——本库不虚构参数，只声明重合及其精度",
    ),
  )
  ops.push(
    coincident(
      "LOCAL:WGS84_GDA94",
      "WGS 84 ↔ GDA94（视为重合，精度随时间下降）",
      "WGS84",
      "GDA94",
      australia(),
      1.0,
      "Geoscience Australia",
      "GDA94 固定于 1994.0 历元，与 WGS84 的差异随板块运动累积（2020 年约 1.8 m）；此处按 1 m 级声明，高精度场景须用 GDA2020",
    ),
  )

  // ── 七参数 ──────────────────────────────────────────────────────
  ops.push(
    seven(
      "LOCAL:OSGB36_WGS84_7P",
      "OSGB36 → WGS 84（7 参数）",
      446.448,
      -125.157,
      542.06,
      0.1502,
      0.247,
      0.8421,
      -20.4894,
      @types.PositionVector,
      "OSGB36",
      "WGS84",
      uk(),
      Some(2.0),
      "PROJ datum table: osgb36",
      "英国本土 2 m 级；亚米级须改用 OSTN15 网格（EPSG:7709）",
    ),
  )
  ops.push(
    seven(
      "LOCAL:OSGB36_ETRS89_7P",
      "OSGB36 → ETRS89（7 参数）",
      446.448,
      -125.157,
      542.06,
      0.1502,
      0.247,
      0.8421,
      -20.4894,
      @types.PositionVector,
      "OSGB36",
      "ETRS89",
      uk(),
      Some(2.0),
      "PROJ datum table: osgb36",
      "与 OSGB36→WGS84 同一套参数，经 WGS84/ETRS89 重合关系转达",
    ),
  )
  ops.push(
    seven(
      "LOCAL:BD72_ETRS89_7P",
      "BD72 → ETRS89（7 参数）",
      -106.8686,
      52.2978,
      -103.7239,
      -0.3366,
      0.457,
      -1.8422,
      1.2747,
      @types.PositionVector,
      "BD72",
      "ETRS89",
      belgium(),
      Some(1.0),
      "PROJ datum table: bd72",
      "比利时全境；高精度成果应改用 BeTA2007 或官方网格",
    ),
  )
  ops.push(
    seven(
      "LOCAL:BD72_WGS84_7P",
      "BD72 → WGS 84（7 参数）",
      -106.8686,
      52.2978,
      -103.7239,
      -0.3366,
      0.457,
      -1.8422,
      1.2747,
      @types.PositionVector,
      "BD72",
      "WGS84",
      belgium(),
      Some(1.0),
      "PROJ datum table: bd72",
      "经 ETRS89 与 WGS84 的重合关系转达",
    ),
  )
  ops.push(
    seven(
      "LOCAL:DHDN_ETRS89_7P",
      "DHDN → ETRS89（7 参数）",
      598.1,
      73.7,
      418.2,
      0.202,
      0.045,
      -2.455,
      6.7,
      @types.PositionVector,
      "DHDN",
      "ETRS89",
      germany(),
      Some(3.0),
      "PROJ datum table: potsdam",
      "德国全境 3 m 级；州级成果应用 BeTA2007 或各州网格",
    ),
  )
  ops.push(
    seven(
      "LOCAL:DHDN_WGS84_7P",
      "DHDN → WGS 84（7 参数）",
      598.1,
      73.7,
      418.2,
      0.202,
      0.045,
      -2.455,
      6.7,
      @types.PositionVector,
      "DHDN",
      "WGS84",
      germany(),
      Some(3.0),
      "PROJ datum table: potsdam",
      "与 DHDN→ETRS89 同一套参数；本库不做多跳串联，因此目标为 WGS84 时需要这条独立记录",
    ),
  )
  ops.push(
    seven(
      "LOCAL:TM65_WGS84_7P",
      "TM65 → WGS 84（7 参数）",
      482.06,
      -130.71,
      564.56,
      -2.235,
      0.622,
      0.624,
      0.696,
      @types.PositionVector,
      "TM65",
      "WGS84",
      ireland(),
      Some(1.0),
      "PROJ datum table: ire65",
      "爱尔兰岛；1 m 级",
    ),
  )
  ops.push(
    seven(
      "LOCAL:WGS72_WGS84_7P",
      "WGS 72 → WGS 84（7 参数）",
      0.0,
      0.0,
      4.5,
      0.0,
      0.0,
      0.554,
      0.2263,
      @types.PositionVector,
      "WGS72",
      "WGS84",
      BoundingBox::world(),
      Some(5.0),
      "PROJ datum table: wgs72",
      "全球；WGS72 已退役，仅用于历史数据",
    ),
  )

  // ── 三参数 ──────────────────────────────────────────────────────
  ops.push(
    three(
      "LOCAL:NAD27_WGS84_CONUS_3P",
      "NAD27 → WGS 84（CONUS 3 参数）",
      -8.0,
      160.0,
      176.0,
      "NAD27",
      "WGS84",
      conus(),
      Some(10.0),
      "PROJ datum table: nad27",
      "美国本土 10 m 级；亚米级必须用 NADCON 网格（EPSG:1241）。阿拉斯加、夏威夷参数不同，不在本条目覆盖内",
    ),
  )
  ops.push(
    three(
      "LOCAL:NAD27_NAD83_CONUS_3P",
      "NAD27 → NAD83（CONUS 3 参数）",
      -8.0,
      160.0,
      176.0,
      "NAD27",
      "NAD83",
      conus(),
      Some(10.0),
      "PROJ datum table: nad27",
      "与 NAD27→WGS84 同一套参数；NADCON 网格版见 EPSG:1241",
    ),
  )
  ops.push(
    three(
      "LOCAL:NAD83_WGS84_3P",
      "NAD83 → WGS 84（3 参数）",
      0.0,
      0.0,
      0.0,
      "NAD83",
      "WGS84",
      north_america(),
      Some(2.0),
      "EPSG Guidance Note 7-2",
      "北美范围内 NAD83 与 WGS84 差 1~2 m，不能用恒等代替",
    ),
  )
  ops.push(
    three(
      "LOCAL:ED50_WGS84_3P",
      "ED50 → WGS 84（3 参数）",
      -87.0,
      -96.0,
      -120.0,
      "ED50",
      "WGS84",
      europe(),
      Some(5.0),
      "PROJ datum table: ed50",
      "欧洲 5 m 级；各国有更精确的本地参数",
    ),
  )
  ops.push(
    three(
      "LOCAL:ED50_ETRS89_3P",
      "ED50 → ETRS89（3 参数）",
      -87.0,
      -96.0,
      -120.0,
      "ED50",
      "ETRS89",
      europe(),
      Some(5.0),
      "PROJ datum table: ed50",
      "同上，目标改记 ETRS89",
    ),
  )
  ops.push(
    three(
      "LOCAL:CH1903_ETRS89_3P",
      "CH1903 → ETRS89（3 参数）",
      674.374,
      15.056,
      405.346,
      "CH1903",
      "ETRS89",
      switzerland(),
      Some(1.0),
      "swisstopo",
      "瑞士官方 3 参数；LV03/LV95 转换另需平面近似公式，本库只做基准层",
    ),
  )
  ops.push(
    three(
      "LOCAL:CH1903_WGS84_3P",
      "CH1903 → WGS 84（3 参数）",
      674.374,
      15.056,
      405.346,
      "CH1903",
      "WGS84",
      switzerland(),
      Some(1.0),
      "swisstopo",
      "经 ETRS89 重合关系转达",
    ),
  )

  // ── 网格改正（需要外部数据文件，没有文件时会在选择阶段被跳过） ──
  ops.push(
    grid(
      "EPSG:7709",
      "OSGB36 → ETRS89（OSTN15 网格）",
      "OSTN15",
      "OSGB36",
      "ETRS89",
      uk(),
      Some(0.1),
      "EPSG:7709",
      "英国官方最高精度路径；需要 OSTN15 的 .gsb 文件，数据不随本库分发",
    ),
  )
  ops.push(
    grid(
      "EPSG:1241",
      "NAD27 → NAD83（NADCON 网格）",
      "NADCON-CONUS",
      "NAD27",
      "NAD83",
      conus(),
      Some(0.15),
      "EPSG:1241",
      "美国官方路径；需要 conus.las/.los 文件，数据不随本库分发",
    ),
  )
  ops
}

///|
/// 按标识查一条运算（不含派生反向）。
pub fn by_code(code : String) -> CoordinateOperation? raise @types.CrsError {
  for op in all() {
    if op.code == code {
      return Some(op)
    }
  }
  None
}

///|
/// 注册表里的基准标识（去重、升序），供 `ops` 与错误提示使用。
pub fn datum_keys() -> Array[String] raise @types.CrsError {
  let keys : Array[String] = []
  for op in all() {
    push_unique(keys, op.source)
    push_unique(keys, op.target)
  }
  sort_strings(keys)
  keys
}

///|
/// 与给定基准有关的全部运算对（形如 `OSGB36 → ETRS89`）。
pub fn partners_of(key : String) -> Array[String] raise @types.CrsError {
  let out : Array[String] = []
  for op in all() {
    if op.source == key {
      push_unique(out, op.target)
    }
    if op.target == key {
      push_unique(out, op.source)
    }
  }
  sort_strings(out)
  out
}

// ── 构造辅助 ────────────────────────────────────────────────────────

///|
/// 恒等运算。
fn coincident(
  code : String,
  name : String,
  source : String,
  target : String,
  area : BoundingBox,
  accuracy : Double,
  authority : String,
  note : String,
) -> CoordinateOperation raise @types.CrsError {
  CoordinateOperation::new(
    code~,
    name~,
    method_kind=Identity,
    params=OperationParams::NoParams,
    source~,
    target~,
    area~,
    accuracy_m=Some(accuracy),
    authority~,
    note~,
  )
}

///|
/// 七参数运算。
fn seven(
  code : String,
  name : String,
  dx : Double,
  dy : Double,
  dz : Double,
  rx : Double,
  ry : Double,
  rz : Double,
  ds : Double,
  convention : @types.RotationConvention,
  source : String,
  target : String,
  area : BoundingBox,
  accuracy : Double?,
  authority : String,
  note : String,
) -> CoordinateOperation raise @types.CrsError {
  CoordinateOperation::new(
    code~,
    name~,
    method_kind=PositionVector7,
    params=OperationParams::Helmert(
      @types.Helmert::new(dx, dy, dz, rx, ry, rz, ds, convention~),
    ),
    source~,
    target~,
    area~,
    accuracy_m=accuracy,
    authority~,
    note~,
  )
}

///|
/// 三参数运算。
fn three(
  code : String,
  name : String,
  dx : Double,
  dy : Double,
  dz : Double,
  source : String,
  target : String,
  area : BoundingBox,
  accuracy : Double?,
  authority : String,
  note : String,
) -> CoordinateOperation raise @types.CrsError {
  CoordinateOperation::new(
    code~,
    name~,
    method_kind=GeocentricTranslation3,
    params=OperationParams::Helmert(@types.Helmert::new(dx, dy, dz, 0.0, 0.0, 0.0, 0.0)),
    source~,
    target~,
    area~,
    accuracy_m=accuracy,
    authority~,
    note~,
  )
}

///|
/// 网格类运算。参数只记逻辑名，实际文件由调用方在运行时提供。
fn grid(
  code : String,
  name : String,
  grid_id : String,
  source : String,
  target : String,
  area : BoundingBox,
  accuracy : Double?,
  authority : String,
  note : String,
) -> CoordinateOperation raise @types.CrsError {
  CoordinateOperation::new(
    code~,
    name~,
    method_kind=Ntv2Grid,
    params=OperationParams::Grid(grid_id),
    source~,
    target~,
    area~,
    accuracy_m=accuracy,
    authority~,
    note~,
  )
}

// ── 适用范围 ────────────────────────────────────────────────────────
// 数值取自 EPSG area of use 的外接矩形，取整到 0.1°。

///|
fn uk() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(49.0, -9.0, 61.0, 2.0)
}

///|
fn conus() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(24.0, -125.0, 50.0, -66.0)
}

///|
fn north_america() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(14.0, -180.0, 84.0, -47.0)
}

///|
fn europe() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(30.0, -40.0, 84.0, 40.0)
}

///|
fn belgium() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(49.4, 2.5, 51.6, 6.5)
}

///|
fn switzerland() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(45.8, 5.9, 47.9, 10.6)
}

///|
fn germany() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(47.2, 5.8, 55.1, 15.1)
}

///|
fn ireland() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(51.3, -10.6, 55.5, -5.9)
}

///|
fn france() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(41.0, -5.5, 51.5, 9.9)
}

///|
fn australia() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(-44.0, 112.0, -10.0, 154.0)
}

///|
fn china() -> BoundingBox raise @types.CrsError {
  BoundingBox::new(18.0, 73.0, 54.0, 135.0)
}

// ── 数组工具 ────────────────────────────────────────────────────────

///|
fn push_unique(arr : Array[String], value : String) -> Unit {
  for item in arr {
    if item == value {
      return
    }
  }
  arr.push(value)
}

///|
/// 字符串插入排序（元素少，不值得引入通用排序）。
fn sort_strings(arr : Array[String]) -> Unit {
  let n = arr.length()
  let mut i = 1
  while i < n {
    let key = arr[i]
    let mut j = i
    while j > 0 && arr[j - 1] > key {
      arr[j] = arr[j - 1]
      j = j - 1
    }
    arr[j] = key
    i = i + 1
  }
}
