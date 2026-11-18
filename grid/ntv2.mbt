// NTv2（`.gsb`）解析。
//
// 格式依据：Geomatics Canada《NTv2 — National Transformation Version 2,
// User's Guide》(1996)。有三条约定容易忽略，错了就是整体错位而不是
// 差一点点，全部在这里显式处理：
//
//   1. 所有角度字段的单位是**角秒**，不是度；
//   2. 网格节点按"从东南角开始，先向西，再向北"排列（不是先向东！）；
//   3. 文件里的经度是**正西**（west longitude positive），
//      与通常的"东经为正"相反。
//
// 第 3 条不靠猜：本库先用"正西"读，再用 east > west 这个自洽条件反证。
// 两种读法不可能同时成立（除非东西界相等，那是坏文件），所以"换一种读法
// 才自洽"就是确定性判据，而不是启发式。判定结果记在 `lon_convention` 里。

///|
/// 文件头与每个子文件头的长度：11 条记录 × 16 字节。
const NTv2_HEADER_BYTES : Int = 176

///|
/// 每个节点的字节数：4 个 float32。
const NTv2_NODE_BYTES : Int = 16

///|
/// 读一个字节，越界时报出偏移与文件长度。
///
/// 用 `get` 而不是下标：下标越界在 wasm 上是 trap，用户看到的是
/// "程序崩了"，看不到"文件在第 240 字节被截断"。
fn byte_at(bytes : Bytes, off : Int, what : String) -> Int raise @types.CrsError {
  match bytes.get(off) {
    Some(v) => v.to_uint().reinterpret_as_int()
    None =>
      raise @types.CrsError::Parse(
        "NTv2 文件不完整：读" +
        what +
        "时越过文件末尾（偏移 " +
        off.to_string() +
        "，文件长 " +
        bytes.length().to_string() +
        " 字节）",
      )
  }
}

///|
/// 读 8 字节文本字段，去掉尾部空格与填充的 0。
fn text_at(bytes : Bytes, off : Int, what : String) -> String raise @types.CrsError {
  let sb = StringBuilder()
  let mut i = 0
  while i < 8 {
    let v = byte_at(bytes, off + i, what)
    if v != 0x20 && v != 0 {
      match v.to_char() {
        Some(c) => sb.write_char(c)
        None => ()
      }
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// 校验某个位置的标签。标签错位说明这不是 NTv2 文件，或者被截断过。
fn expect_label(
  bytes : Bytes,
  off : Int,
  want : String,
  place : String,
) -> Unit raise @types.CrsError {
  let got = text_at(bytes, off, "标签")
  if got != want {
    raise @types.CrsError::Parse(
      "NTv2 结构不符：" +
      place +
      "的标签是 \"" +
      got +
      "\"，期望 \"" +
      want +
      "\"。文件可能不是 NTv2(.gsb)，或被截断、拼接坏了",
    )
  }
}

///|
/// 读小端 int32。
fn i32_at(bytes : Bytes, off : Int, what : String) -> Int raise @types.CrsError {
  let b0 = byte_at(bytes, off, what).reinterpret_as_uint()
  let b1 = byte_at(bytes, off + 1, what).reinterpret_as_uint()
  let b2 = byte_at(bytes, off + 2, what).reinterpret_as_uint()
  let b3 = byte_at(bytes, off + 3, what).reinterpret_as_uint()
  (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).reinterpret_as_int()
}

///|
/// 读小端 float64。
fn f64_at(bytes : Bytes, off : Int, what : String) -> Double raise @types.CrsError {
  let mut v : UInt64 = 0UL
  let mut i = 0
  while i < 8 {
    v = v | (byte_at(bytes, off + i, what).to_uint64() << (i * 8))
    i = i + 1
  }
  v.reinterpret_as_double()
}

///|
/// 读小端 float32。
fn f32_at(bytes : Bytes, off : Int, what : String) -> Float raise @types.CrsError {
  let b0 = byte_at(bytes, off, what).reinterpret_as_uint()
  let b1 = byte_at(bytes, off + 1, what).reinterpret_as_uint()
  let b2 = byte_at(bytes, off + 2, what).reinterpret_as_uint()
  let b3 = byte_at(bytes, off + 3, what).reinterpret_as_uint()
  Float::reinterpret_from_int((b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).reinterpret_as_int())
}

///|
/// 四舍五入成整数（只用于正数）。
fn round_i(x : Double) -> Int {
  (x + 0.5).to_int()
}

///|
/// 解析一个 NTv2 网格。
///
/// `name` 只用于报告（通常是文件名），不参与任何计算。
pub fn Ntv2Grid::parse(
  bytes : Bytes,
  name~ : String = "",
) -> Ntv2Grid raise @types.CrsError {
  if bytes.length() < NTv2_HEADER_BYTES {
    raise @types.CrsError::Parse(
      "NTv2 文件太短：" +
      bytes.length().to_string() +
      " 字节，仅文件头就需要 " +
      NTv2_HEADER_BYTES.to_string() +
      " 字节。这不是 .gsb 文件",
    )
  }
  expect_label(bytes, 0, "NUM_OREC", "文件头第 1 条记录")
  let orec = i32_at(bytes, 8, "NUM_OREC")
  if orec != 11 {
    // 大端文件把 11 写成 0B 00 00 00，按小端读出来是 184549376。
    if orec == 184549376 {
      raise @types.CrsError::Parse(
        "NTv2 文件是大端字节序，本库只读小端。请先用 GDAL 或官方工具转成小端",
      )
    }
    raise @types.CrsError::Parse(
      "NUM_OREC = " +
      orec.to_string() +
      "，期望 11。文件头记录数不符，可能不是 NTv2 文件",
    )
  }
  expect_label(bytes, 16, "NUM_SREC", "文件头第 2 条记录")
  let srec = i32_at(bytes, 24, "NUM_SREC")
  if srec != 11 {
    raise @types.CrsError::Parse(
      "NUM_SREC = " + srec.to_string() + "，期望 11。子文件头记录数不符",
    )
  }
  expect_label(bytes, 32, "NUM_FILE", "文件头第 3 条记录")
  let nfile = i32_at(bytes, 40, "NUM_FILE")
  if nfile < 1 {
    raise @types.CrsError::Parse("NUM_FILE = " + nfile.to_string() + "，文件里没有子网格")
  }
  expect_label(bytes, 48, "GS_TYPE", "文件头第 4 条记录")
  let gs_type = text_at(bytes, 56, "GS_TYPE")
  if !gs_type.has_prefix("SECONDS") {
    raise @types.CrsError::Parse(
      "GS_TYPE = \"" + gs_type + "\"，本库只支持 SECONDS。MINUTES / DEGREES 文件需先转换",
    )
  }
  expect_label(bytes, 64, "VERSION", "文件头第 5 条记录")
  let version = text_at(bytes, 72, "VERSION")
  if !version.has_prefix("NTv2") {
    raise @types.CrsError::Parse(
      "VERSION = \"" + version + "\"，只支持 NTv2（NTv1 的 .dat 是另一种布局）",
    )
  }
  expect_label(bytes, 80, "SYSTEM_F", "文件头第 6 条记录")
  expect_label(bytes, 96, "SYSTEM_T", "文件头第 7 条记录")
  expect_label(bytes, 112, "MAJOR_F", "文件头第 8 条记录")
  expect_label(bytes, 128, "MINOR_F", "文件头第 9 条记录")
  expect_label(bytes, 144, "MAJOR_T", "文件头第 10 条记录")
  expect_label(bytes, 160, "MINOR_T", "文件头第 11 条记录")
  let from_system = text_at(bytes, 88, "SYSTEM_F")
  let to_system = text_at(bytes, 104, "SYSTEM_T")
  let major_f = f64_at(bytes, 120, "MAJOR_F")
  let minor_f = f64_at(bytes, 136, "MINOR_F")
  let major_t = f64_at(bytes, 152, "MAJOR_T")
  let minor_t = f64_at(bytes, 168, "MINOR_T")
  let subs : Array[SubGrid] = []
  let mut lon_convention = ""
  let mut off = NTv2_HEADER_BYTES
  let mut idx = 0
  while idx < nfile {
    let place = "第 " + (idx + 1).to_string() + " 个子文件头"
    expect_label(bytes, off, "SUB_NAME", place)
    let sub_name = text_at(bytes, off + 8, "SUB_NAME")
    expect_label(bytes, off + 16, "PARENT", place)
    let parent = text_at(bytes, off + 24, "PARENT")
    expect_label(bytes, off + 32, "CREATED", place)
    expect_label(bytes, off + 48, "UPDATED", place)
    expect_label(bytes, off + 64, "S_LAT", place)
    expect_label(bytes, off + 80, "N_LAT", place)
    expect_label(bytes, off + 96, "E_LONG", place)
    expect_label(bytes, off + 112, "W_LONG", place)
    expect_label(bytes, off + 128, "LAT_INC", place)
    expect_label(bytes, off + 144, "LONG_INC", place)
    expect_label(bytes, off + 160, "GS_COUNT", place)
    let s_lat = f64_at(bytes, off + 72, "S_LAT")
    let n_lat = f64_at(bytes, off + 88, "N_LAT")
    let e_long = f64_at(bytes, off + 104, "E_LONG")
    let w_long = f64_at(bytes, off + 120, "W_LONG")
    let lat_inc = f64_at(bytes, off + 136, "LAT_INC")
    let lon_inc = f64_at(bytes, off + 152, "LONG_INC")
    let gs_count = i32_at(bytes, off + 168, "GS_COUNT")
    let south = s_lat / 3600.0
    let north = n_lat / 3600.0
    let lat_step = lat_inc / 3600.0
    let lon_step = lon_inc / 3600.0
    if lat_step <= 0.0 || lon_step <= 0.0 {
      raise @types.CrsError::Parse(
        "子网格 " +
        sub_name +
        " 的格距非正：LAT_INC = " +
        lat_inc.to_string() +
        "，LONG_INC = " +
        lon_inc.to_string(),
      )
    }
    if south >= north {
      raise @types.CrsError::Parse(
        "子网格 " +
        sub_name +
        " 的南北界自相矛盾：S_LAT = " +
        s_lat.to_string() +
        "，N_LAT = " +
        n_lat.to_string(),
      )
    }
    // 正西读法：east = -E_LONG，west = -W_LONG；正东读法相反。
    // 只有一种能同时满足 east > west，所以这是排除，不是猜。
    let east_pw = -e_long / 3600.0
    let west_pw = -w_long / 3600.0
    let east_pe = e_long / 3600.0
    let west_pe = w_long / 3600.0
    let use_pe = if east_pw > west_pw {
      false
    } else if east_pe > west_pe {
      true
    } else {
      raise @types.CrsError::Parse(
        "子网格 " +
        sub_name +
        " 的东西界自相矛盾：E_LONG = " +
        e_long.to_string() +
        "，W_LONG = " +
        w_long.to_string() +
        "。两种经度约定下都得不到 east > west",
      )
    }
    let this_conv = if use_pe { "east-positive" } else { "west-positive" }
    if lon_convention == "" {
      lon_convention = this_conv
    } else if lon_convention != this_conv {
      raise @types.CrsError::Parse(
        "同一文件内子网格的经度约定不一致（" +
        lon_convention +
        " 与 " +
        this_conv +
        "）。这种文件不能按单一约定解释，请换用官方原始文件",
      )
    }
    let east = if use_pe { east_pe } else { east_pw }
    let west = if use_pe { west_pe } else { west_pw }
    if east < -180.0 || west < -180.0 || east > 180.0 || west > 180.0 {
      raise @types.CrsError::Parse(
        "子网格 " +
        sub_name +
        " 的经度超出 [-180, 180]：" +
        west.to_string() +
        " .. " +
        east.to_string(),
      )
    }
    let nrows = round_i((north - south) / lat_step) + 1
    let ncols = round_i((east - west) / lon_step) + 1
    if nrows < 2 || ncols < 2 {
      raise @types.CrsError::Parse(
        "子网格 " +
        sub_name +
        " 太小（" +
        nrows.to_string() +
        " 行 × " +
        ncols.to_string() +
        " 列）：插值至少需要 2 行 2 列",
      )
    }
    let expect_count = nrows * ncols
    if gs_count != expect_count {
      raise @types.CrsError::Parse(
        "子网格 " +
        sub_name +
        " 的 GS_COUNT = " +
        gs_count.to_string() +
        "，但按范围与格距算出的节点数是 " +
        expect_count.to_string() +
        "（" +
        nrows.to_string() +
        " 行 × " +
        ncols.to_string() +
        " 列）。文件可能被截断或改坏",
      )
    }
    let data_off = off + NTv2_HEADER_BYTES
    let need = data_off + gs_count * NTv2_NODE_BYTES
    if need > bytes.length() {
      raise @types.CrsError::Parse(
        "子网格 " +
        sub_name +
        " 的节点数据被截断：需要到偏移 " +
        need.to_string() +
        "，文件只有 " +
        bytes.length().to_string() +
        " 字节",
      )
    }
    let cells = FixedArray::make(gs_count * 4, 0.0F)
    let mut k = 0
    while k < gs_count {
      let base = data_off + k * NTv2_NODE_BYTES
      cells[k * 4] = f32_at(bytes, base, "节点纬改正")
      cells[k * 4 + 1] = f32_at(bytes, base + 4, "节点经改正")
      cells[k * 4 + 2] = f32_at(bytes, base + 8, "节点纬精度")
      cells[k * 4 + 3] = f32_at(bytes, base + 12, "节点经精度")
      k = k + 1
    }
    subs.push(
      {
        name: sub_name,
        parent,
        south,
        west,
        north,
        east,
        lat_inc: lat_step,
        lon_inc: lon_step,
        nrows,
        ncols,
        cells,
      },
    )
    off = need
    idx = idx + 1
  }
  {
    name,
    version,
    from_system,
    to_system,
    from_ellipsoid: (major_f, minor_f),
    to_ellipsoid: (major_t, minor_t),
    subs,
    lon_convention,
  }
}
