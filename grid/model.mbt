// 网格改正的数据模型。
//
// 这一层不碰文件系统：解析只接受字节，读文件由调用方完成。这样同一套
// 解析与插值代码在 wasm / js / native 上行为一致，也让测试可以完全
// 用内存里的字节造文件，不需要往仓库里塞第三方数据。

///|
/// 一次网格改正的结果。
pub(all) struct GridShift {
  /// 经度改正量（度，东经为正）。
  dlon : Double
  /// 纬度改正量（度，正北为正）。
  dlat : Double
  /// 命中的子网格名。报告里要写出来，否则用户无法复查。
  subgrid : String
  /// 迭代次数：正向恒为 1，反解才可能大于 1。
  iterations : Int
}

///|
/// 一个子网格。
///
/// 字段全部存成"度"和"度/格"，而不是文件里的角秒：角秒只在解析那一处
/// 出现一次，之后全库统一用度，免得某处忘了除 3600。
pub(all) struct SubGrid {
  /// 子网格名（文件内 8 字符，已去尾部空格）。
  name : String
  /// 父网格名；根网格为 `"NONE"`。
  parent : String
  south : Double
  west : Double
  north : Double
  east : Double
  /// 纬向格距（度）。
  lat_inc : Double
  /// 经向格距（度，正值；列号向西递增）。
  lon_inc : Double
  nrows : Int
  ncols : Int
  /// 每个节点 4 个 float32：纬改正、经改正（角秒，正西）、纬精度、经精度。
  ///
  /// 精度字段保留但不对外暴露：NTv2 规范没有把它的单位钉死，部分文件写
  /// 米、部分写角秒。拿一个单位不确定的数做精度承诺比不给更糟。
  cells : FixedArray[Float]
}

///|
/// 子网格是否覆盖该点（含边界）。
pub fn SubGrid::contains(self : SubGrid, lon : Double, lat : Double) -> Bool {
  lat >= self.south && lat <= self.north && lon >= self.west && lon <= self.east
}

///|
/// 子网格面积（平方度）。只用于"多个网格都覆盖该点时取最小的那个"。
pub fn SubGrid::area(self : SubGrid) -> Double {
  (self.north - self.south) * (self.east - self.west)
}

///|
/// 是否为根网格（没有父网格）。
pub fn SubGrid::is_root(self : SubGrid) -> Bool {
  self.parent == "NONE" || self.parent == ""
}

///|
/// 范围文本，报错与 `describe` 用。
pub fn SubGrid::to_text(self : SubGrid) -> String {
  self.name +
  " [" +
  self.south.to_string() +
  ", " +
  self.west.to_string() +
  "] .. [" +
  self.north.to_string() +
  ", " +
  self.east.to_string() +
  "]"
}

///|
/// 一个 NTv2 网格文件（可含多个子网格）。
pub(all) struct Ntv2Grid {
  /// 来源标识（文件名），只用于报告。
  name : String
  version : String
  from_system : String
  to_system : String
  /// 源椭球 (a, b)，米。
  from_ellipsoid : (Double, Double)
  /// 目标椭球 (a, b)，米。
  to_ellipsoid : (Double, Double)
  /// 文件实际采用的经度约定：`west-positive`（规范默认）或 `east-positive`
  /// （部分非加拿大产的文件）。读出来是为了让报告能如实写清"这份数据是怎么
  /// 解释的"，而不是让约定藏在代码里。
  lon_convention : String
  subs : Array[SubGrid]
}

///|
/// 网格总数。
pub fn Ntv2Grid::len(self : Ntv2Grid) -> Int {
  self.subs.length()
}

///|
/// 全部子网格覆盖范围的外接矩形 `(south, west, north, east)`。
pub fn Ntv2Grid::extent(self : Ntv2Grid) -> (Double, Double, Double, Double) {
  let mut south = 90.0
  let mut west = 180.0
  let mut north = -90.0
  let mut east = -180.0
  for s in self.subs {
    if s.south < south {
      south = s.south
    }
    if s.west < west {
      west = s.west
    }
    if s.north > north {
      north = s.north
    }
    if s.east > east {
      east = s.east
    }
  }
  (south, west, north, east)
}

///|
/// 找出覆盖该点的子网格。
///
/// 多个子网格重叠时取面积最小的那个：NTv2 的子网格就是"局部加密"，
/// 小的那个精度更高。重叠区取大的会把加密区浪费掉。
pub fn Ntv2Grid::find(self : Ntv2Grid, lon : Double, lat : Double) -> SubGrid? {
  let mut best : SubGrid? = None
  for s in self.subs {
    if s.contains(lon, lat) {
      let better = match best {
        None => true
        Some(b) => s.area() < b.area()
      }
      if better {
        best = Some(s)
      }
    }
  }
  best
}

///|
/// 一组已加载的网格，按标识索引。
///
/// 标识由调用方决定（注册表里的 `OperationParams::Grid("OSTN15")` 就是
/// 按这个标识找数据）。用文件名当键是错的：文件名是用户起的，拿它当
/// 内部约定等于让用户猜。这里用有序数组而不是哈希表，代价是线性查找，
/// 收益是遍历顺序确定——报告和报错文本才能逐字复现。
pub(all) struct GridSet {
  entries : Array[(String, Ntv2Grid)]
}

///|
/// 空集合。
pub fn GridSet::empty() -> GridSet {
  { entries: [] }
}

///|
/// 登记一个网格。同名覆盖，便于"先加默认、再显式替换"。
pub fn GridSet::add(self : GridSet, id : String, grid : Ntv2Grid) -> Unit {
  let mut i = 0
  let mut replaced = false
  while i < self.entries.length() {
    if self.entries[i].0 == id {
      self.entries[i] = (id, grid)
      replaced = true
    }
    i = i + 1
  }
  if !replaced {
    self.entries.push((id, grid))
  }
}

///|
/// 按标识取网格。
pub fn GridSet::get(self : GridSet, id : String) -> Ntv2Grid? {
  let mut i = 0
  while i < self.entries.length() {
    if self.entries[i].0 == id {
      return Some(self.entries[i].1)
    }
    i = i + 1
  }
  None
}

///|
/// 是否登记了该标识。
pub fn GridSet::contains(self : GridSet, id : String) -> Bool {
  match self.get(id) {
    Some(_) => true
    None => false
  }
}

///|
/// 是否一个网格都没有。
pub fn GridSet::is_empty(self : GridSet) -> Bool {
  self.entries.length() == 0
}

///|
/// 已登记的标识，按字典序排列（保证报错文本与报告逐字可复现）。
pub fn GridSet::ids(self : GridSet) -> Array[String] {
  let out : Array[String] = []
  for e in self.entries {
    out.push(e.0)
  }
  out.sort()
  out
}


