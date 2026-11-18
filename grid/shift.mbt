// 网格改正的执行：双线性插值与反解。
//
// 为什么是双线性而不是样条：NTv2 的网格是"按节点给的改正量"，规范本身
// 只定义了双线性。换成更高阶的插值会在数据稀疏区造出不存在的起伏——
// 那不是更准，那是更自信。

///|
/// 取一个节点的改正量 `(纬, 经)`，单位角秒，经度为正西。
fn SubGrid::node_at(self : SubGrid, r : Int, c : Int) -> (Double, Double) {
  let i = (r * self.ncols + c) * 4
  (self.cells[i].to_double(), self.cells[i + 1].to_double())
}

///|
/// 在单个子网格上求改正量。
///
/// 返回 `None` 表示点落在网格外：**不外推**。节点外的改正量没有定义，
/// 外推出来的数看着连续、其实没有任何数据支撑，比报错危险得多。
pub fn SubGrid::shift(self : SubGrid, lon : Double, lat : Double) -> GridShift? {
  // 列号从东边界起算、向西递增；行号从南边界起算、向北递增。
  let fx = (self.east - lon) / self.lon_inc
  let fy = (lat - self.south) / self.lat_inc
  let cmax = (self.ncols - 1).to_double()
  let rmax = (self.nrows - 1).to_double()
  if fx < 0.0 || fx > cmax || fy < 0.0 || fy > rmax {
    return None
  }
  let c0 = fx.to_int()
  let r0 = fy.to_int()
  let c1 = if c0 + 1 < self.ncols { c0 + 1 } else { c0 }
  let r1 = if r0 + 1 < self.nrows { r0 + 1 } else { r0 }
  let tc = fx - c0.to_double()
  let tr = fy - r0.to_double()
  let n00 = self.node_at(r0, c0)
  let n01 = self.node_at(r0, c1)
  let n10 = self.node_at(r1, c0)
  let n11 = self.node_at(r1, c1)
  let w00 = (1.0 - tc) * (1.0 - tr)
  let w01 = tc * (1.0 - tr)
  let w10 = (1.0 - tc) * tr
  let w11 = tc * tr
  let lat_shift = n00.0 * w00 + n01.0 * w01 + n10.0 * w10 + n11.0 * w11
  let lon_shift = n00.1 * w00 + n01.1 * w01 + n10.1 * w10 + n11.1 * w11
  Some({
    // 文件里的经改正以正西为正，对外统一成东经为正。
    dlon: -lon_shift / 3600.0,
    dlat: lat_shift / 3600.0,
    subgrid: self.name,
    iterations: 1,
  })
}

///|
/// 在整个文件上求改正量（自动挑覆盖该点的最小子网格）。
pub fn Ntv2Grid::forward(self : Ntv2Grid, lon : Double, lat : Double) -> GridShift? {
  match self.find(lon, lat) {
    Some(s) => s.shift(lon, lat)
    None => None
  }
}

///|
/// 反解：给定目标基准上的坐标，求源基准上的坐标。
///
/// 网格只给了"源 → 目标"的正向改正，反解没有闭式解，只能用不动点迭代
/// `p ← target - shift(p)`。改正量是缓变的（每格几角秒），所以三步内就
/// 收敛；这里给到 12 步并检查最终残差，不收敛就返回 `None`——
/// 宁可让调用方拿到"这条链路在这点不可用"，也不返回一个没收敛的数。
pub fn Ntv2Grid::unshift(self : Ntv2Grid, lon : Double, lat : Double) -> GridShift? {
  let mut plon = lon
  let mut plat = lat
  let mut it = 0
  let mut used = ""
  let mut converged = false
  while it < 12 {
    let s = match self.forward(plon, plat) {
      Some(s) => s
      None => return None
    }
    used = s.subgrid
    let next_lon = lon - s.dlon
    let next_lat = lat - s.dlat
    it = it + 1
    let step_lon = (next_lon - plon).abs()
    let step_lat = (next_lat - plat).abs()
    plon = next_lon
    plat = next_lat
    if step_lon < 1.0e-13 && step_lat < 1.0e-13 {
      converged = true
      break
    }
  }
  if !converged {
    return None
  }
  Some({ dlon: plon - lon, dlat: plat - lat, subgrid: used, iterations: it })
}

///|
/// 按方向执行。`reversed` 与 `CoordinateOperation.reversed` 同义。
pub fn Ntv2Grid::apply(
  self : Ntv2Grid,
  lon : Double,
  lat : Double,
  reversed~ : Bool = false,
) -> GridShift? {
  if reversed {
    self.unshift(lon, lat)
  } else {
    self.forward(lon, lat)
  }
}

///|
/// 覆盖范围文本，报错时用。
pub fn Ntv2Grid::coverage_text(self : Ntv2Grid) -> String {
  let e = self.extent()
  "[" +
  e.0.to_string() +
  ", " +
  e.1.to_string() +
  "] .. [" +
  e.2.to_string() +
  ", " +
  e.3.to_string() +
  "]"
}

///|
/// 越界时的解释文本：说清"点在哪、网格覆盖到哪、子网格有几个"。
pub fn Ntv2Grid::outside_message(self : Ntv2Grid, lon : Double, lat : Double) -> String {
  "点 (" +
  lon.to_string() +
  ", " +
  lat.to_string() +
  ") 不在网格 " +
  self.name +
  " 的覆盖范围内（" +
  self.coverage_text() +
  "，" +
  self.subs.length().to_string() +
  " 个子网格）。网格不外推：节点之外的改正量没有数据支撑"
}
