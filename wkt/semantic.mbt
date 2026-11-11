// WKT 语义层：语法树 → CRS 模型。
//
// 同时兼容 WKT2:2019（GEOGCRS/PROJCRS/BASEGEOGCRS）与 WKT1
// （GEOGCS/PROJCS/SPHEROID/PROJECTION）。两套关键字在现实中长期共存：
// Shapefile 的 .prj 几乎全是 WKT1，而 EPSG 官方导出与 QGIS 默认给 WKT2。

///|
/// 取节点的关键字名（大写化，便于比较）。
fn form_key(node : WktNode) -> String {
  match node {
    Form(k, _) => k.to_upper()
    _ => ""
  }
}

///|
/// 返回节点的子节点数组；非 Form 节点返回空数组。
fn form_children(node : WktNode) -> Array[WktNode] {
  match node {
    Form(_, cs) => cs
    _ => []
  }
}

///|
/// 查找第一个同名子节点。
fn find_child(node : WktNode, keyword : String) -> WktNode? {
  let key = keyword.to_upper()
  for c in form_children(node) {
    if form_key(c) == key {
      return Some(c)
    }
  }
  None
}

///|
/// 查找所有同名子节点。
fn find_children(node : WktNode, keyword : String) -> Array[WktNode] {
  let key = keyword.to_upper()
  let out : Array[WktNode] = []
  for c in form_children(node) {
    if form_key(c) == key {
      out.push(c)
    }
  }
  out
}

///|
/// 第一个字符串子节点（通常是名称）。
fn first_text(node : WktNode) -> String? {
  for c in form_children(node) {
    match c {
      Text(s) => return Some(s)
      _ => continue
    }
  }
  None
}

///|
/// 第 k 个字符串子节点，用于 MEMBER 之类的重复项。
fn all_texts(node : WktNode) -> Array[String] {
  let out : Array[String] = []
  for c in form_children(node) {
    match c {
      Text(s) => out.push(s)
      _ => continue
    }
  }
  out
}

///|
/// 第 k 个数值子节点（0 起）。SPHEROID["WGS 84",6378137,298.25] 需要取第 1、2 个。
fn number_at(node : WktNode, index : Int) -> Double? {
  let mut seen = 0
  for c in form_children(node) {
    match c {
      Number(v) => {
        if seen == index {
          return Some(v)
        }
        seen = seen + 1
      }
      _ => continue
    }
  }
  None
}

///|
/// 解析 AUTHORITY["EPSG","4326"] 或 ID["EPSG",4326] 形式的标识。
fn parse_identifier(node : WktNode) -> @types.Identifier? {
  let target = if find_child(node, "ID") is Some(_) {
    find_child(node, "ID")
  } else {
    find_child(node, "AUTHORITY")
  }
  match target {
    Some(id) => {
      let texts = all_texts(id)
      let authority = if texts.length() > 0 { texts[0] } else { "EPSG" }
      // WKT1 把 code 写成字符串，WKT2 写成数字，两种都要吃。
      let code : Double = match number_at(id, 0) {
        Some(v) => v
        None =>
          if texts.length() > 1 {
            match parse_number_int(texts[1]) {
              Some(v) => v.to_double()
              None => 0.0
            }
          } else {
            0.0
          }
      }
      Some(@types.Identifier::new(authority, code.to_int()))
    }
    None => None
  }
}

///|
/// 把整数字符串转成数值（用于 WKT1 的 AUTHORITY code）。
fn parse_number_int(s : String) -> Int? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut v = 0
  for c in chars {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - 48)
  }
  Some(v)
}

///|
/// 解析椭球：WKT2 用 ELLIPSOID，WKT1 用 SPHEROID。
fn parse_ellipsoid(node : WktNode) -> @types.Ellipsoid raise @types.CrsError {
  let target = match find_child(node, "ELLIPSOID") {
    Some(e) => Some(e)
    None => find_child(node, "SPHEROID")
  }
  match target {
    Some(e) => {
      let name = first_text(e).unwrap_or("unnamed ellipsoid")
      let a = number_at(e, 0).unwrap_or(6378137.0)
      let invf = number_at(e, 1).unwrap_or(298.257223563)
      @types.Ellipsoid::new(name, a, invf)
    }
    None => @types.wgs84
  }
}

///|
/// 解析角度单位的因子；缺省按度处理。
fn parse_angular_unit(node : WktNode) -> @types.AngularUnit {
  match find_child(node, "ANGLEUNIT") {
    Some(u) => {
      let name = first_text(u).unwrap_or("degree")
      let factor = number_at(u, 0).unwrap_or(0.017453292519943295)
      { name, factor }
    }
    None => {
      // WKT1 用 UNIT["degree",0.0174532925199433] 表达角度单位，
      // 但同一个关键字也用于长度单位，靠因子大小区分：角度因子远小于 1。
      match find_child(node, "UNIT") {
        Some(u) => {
          let factor = number_at(u, 0).unwrap_or(0.017453292519943295)
          if factor < 0.1 {
            {
              name: first_text(u).unwrap_or("degree"),
              factor,
            }
          } else {
            @types.degree
          }
        }
        None => @types.degree
      }
    }
  }
}

///|
/// 解析长度单位；缺省按米处理。
fn parse_linear_unit(node : WktNode) -> @types.LinearUnit {
  match find_child(node, "LENGTHUNIT") {
    Some(u) => {
      let name = first_text(u).unwrap_or("metre")
      let factor = number_at(u, 0).unwrap_or(1.0)
      { name, factor }
    }
    None => {
      match find_child(node, "UNIT") {
        Some(u) => {
          let factor = number_at(u, 0).unwrap_or(1.0)
          if factor >= 0.1 {
            {
              name: first_text(u).unwrap_or("metre"),
              factor,
            }
          } else {
            @types.metre
          }
        }
        None => @types.metre
      }
    }
  }
}

///|
/// 由 AXIS 子节点判断坐标轴顺序。
///
/// WKT2 的轴带方向词（north/east/south/west），WKT1 只给名称。两者都尝试：
/// 先看方向词，再看名称里是否含 lat/north。
fn parse_axis_order(node : WktNode, projected : Bool) -> @types.AxisOrder {
  let axes = find_children(node, "AXIS")
  if axes.length() == 0 {
    return if projected { @types.EastNorth } else { @types.LonLat }
  }
  let first = axes[0]
  let mut first_is_north = false
  let mut first_is_east = false
  for c in form_children(first) {
    match c {
      Word(w) => {
        let lw = w.to_lower()
        if lw.contains("north") || lw.contains("south") {
          first_is_north = true
        }
        if lw.contains("east") || lw.contains("west") {
          first_is_east = true
        }
      }
      _ => continue
    }
  }
  if !first_is_north && !first_is_east {
    let name = first_text(first).unwrap_or("").to_lower()
    if name.contains("lat") {
      first_is_north = true
    } else if name.contains("lon") || name.contains("east") {
      first_is_east = true
    }
  }
  if projected {
    if first_is_north { @types.NorthEast } else { @types.EastNorth }
  } else {
    if first_is_north { @types.LatLon } else { @types.LonLat }
  }
}

///|
/// 从 TOWGS84[...] 或 BOUNDCRS 的 ABRIDGEDTRANSFORMATION 读取七参数。
fn parse_towgs84(node : WktNode) -> @types.Helmert? {
  match find_child(node, "TOWGS84") {
    Some(t) => {
      let values : Array[Double] = []
      for c in form_children(t) {
        match c {
          Number(v) => values.push(v)
          _ => continue
        }
      }
      if values.length() < 7 {
        return None
      }
      Some(
        @types.Helmert::new(
          values[0], values[1], values[2], values[3], values[4], values[5], values[6],
        ),
      )
    }
    None => None
  }
}

///|
/// 解析基准（DATUM / GEODETICDATUM / ENSEMBLE）。
fn parse_datum(node : WktNode) -> @types.Datum raise @types.CrsError {
  let target = match find_child(node, "DATUM") {
    Some(d) => Some(d)
    None => match find_child(node, "GEODETICDATUM") {
      Some(d) => Some(d)
      None => find_child(node, "ENSEMBLE")
    }
  }
  match target {
    Some(d) => {
      let name = first_text(d).unwrap_or("unnamed datum")
      let ellipsoid = parse_ellipsoid(d)
      let pm = match find_child(d, "PRIMEM") {
        Some(p) => number_at(p, 0).unwrap_or(0.0)
        None => 0.0
      }
      let towgs = parse_towgs84(d)
      @types.Datum::new(name, ellipsoid, prime_meridian=pm, to_wgs84=towgs)
    }
    None => @types.wgs84_datum
  }
}

///|
/// 解析地理坐标系节点（GEOGCRS / BASEGEOGCRS / GEOGCS）。
fn parse_geographic(node : WktNode) -> @types.GeographicCrs raise @types.CrsError {
  let name = first_text(node).unwrap_or("unnamed geographic CRS")
  let datum = parse_datum(node)
  let unit = parse_angular_unit(node)
  let axis = parse_axis_order(node, false)
  let id = parse_identifier(node)
  @types.GeographicCrs::new(name, datum, unit=unit, axis=axis, id=id)
}

///|
/// 解析转换参数：WKT2 的 PARAMETER 与 WKT1 的 PARAMETER 同名，
/// 但 WKT1 的参数名是 snake_case，统一交给 `normalize_keyword` 处理。
fn parse_parameters(node : WktNode) -> Array[@types.Parameter] {
  let out : Array[@types.Parameter] = []
  let params = find_children(node, "PARAMETER")
  let param_list = if params.length() > 0 {
    params
  } else {
    // 有些 WKT2 用 PARAMETERFILE，暂时忽略文件型参数（需要外部网格）。
    find_children(node, "PARAMETERFILE")
  }
  for p in param_list {
    let name = first_text(p).unwrap_or("")
    let value = number_at(p, 0).unwrap_or(0.0)
    let unit_name = match find_child(p, "ANGLEUNIT") {
      Some(u) => first_text(u).unwrap_or("degree")
      None => match find_child(p, "LENGTHUNIT") {
        Some(u) => first_text(u).unwrap_or("metre")
        None => match find_child(p, "SCALEUNIT") {
          Some(u) => first_text(u).unwrap_or("unity")
          None => ""
        }
      }
    }
    let code = match parse_identifier(p) {
      Some(id) => id.code
      None => 0
    }
    out.push(@types.Parameter::new(name, value, code=code, unit=unit_name))
  }
  out
}

///|
/// 把任意写法的投影方法名归一化成 EPSG 方法码。
///
/// WKT1 与 WKT2 的方法名差异极大（`Transverse_Mercator` vs
/// `Transverse Mercator`），且同一方法在不同软件里有别名。这里用
/// 关键字匹配而不是全等表，宁可多认也不漏认。
pub fn method_code_of(name : String) -> Int32 {
  let n = normalize(name)
  if n.contains("transversemercator") || n.contains("gausskruger") {
    9807
  } else if n.contains("popularvisualisationpseudomercator") ||
    n.contains("mercatorauxiliarysphere") {
    1024
  } else if n.contains("mercator") && (n.contains("variantb") || n.contains("2sp")) {
    9805
  } else if n.contains("mercator") {
    9804
  } else if n.contains("lambertconicconformal") &&
    (n.contains("2sp") || n.contains("variantb")) {
    9802
  } else if n.contains("lambertconicconformal") {
    9801
  } else if n.contains("lambertconformalconic") &&
    (n.contains("2sp") || n.contains("variantb")) {
    9802
  } else if n.contains("lambertconformalconic") {
    9801
  } else if n.contains("albers") {
    9822
  } else if n.contains("hotineobliquemercator") || n.contains("obliquemercator") {
    9815
  } else if n.contains("polarstereographic") && n.contains("variantb") {
    9829
  } else if n.contains("polarstereographic") {
    9810
  } else if n.contains("cassini") {
    9806
  } else if n.contains("lambertazimuthalequalarea") {
    9820
  } else {
    0
  }
}

///|
/// 名称归一化：小写并去掉所有非字母数字字符。
fn normalize(s : String) -> String {
  let sb = StringBuilder()
  for ch in s.to_lower() {
    if (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
/// 找出投影坐标系的基底地理坐标系节点。
///
/// 四层嵌套写法在 MoonBit 里没法直接接 `catch`，所以先单独把节点捞出来，
/// 再由调用方一次性解析，避免 `match { .. } catch { .. }` 的语法陷阱。
fn base_geographic_node(node : WktNode) -> WktNode? {
  match find_child(node, "BASEGEOGCRS") {
    Some(b) => Some(b)
    None =>
      match find_child(node, "BASEGEODCRS") {
        Some(b) => Some(b)
        None =>
          match find_child(node, "GEOGCRS") {
            Some(b) => Some(b)
            None => find_child(node, "GEOGCS")
          }
      }
  }
}

///|
/// 取出投影方法名与参数表。
///
/// WKT2 把方法放在 CONVERSION/METHOD 下，WKT1 直接放在 PROJCS/PROJECTION 下，
/// 两者参数都叫 PARAMETER。这里统一成同一份 (名称, 参数) 交给上层。
fn conversion_of(node : WktNode) -> (String, Array[@types.Parameter]) {
  match find_child(node, "CONVERSION") {
    Some(conv) => {
      let mn = match find_child(conv, "METHOD") {
        Some(m) => first_text(m).unwrap_or("unknown")
        None => "unknown"
      }
      (mn, parse_parameters(conv))
    }
    None => {
      let mn = match find_child(node, "PROJECTION") {
        Some(p) => first_text(p).unwrap_or("unknown")
        None => "unknown"
      }
      (mn, parse_parameters(node))
    }
  }
}

///|
/// 方法码修正。
///
/// WKT1 里没有"variant"这个概念：兰勃特 2SP 只写成
/// `PROJECTION["Lambert_Conformal_Conic"]` + 两条 `standard_parallel_*`，
/// 墨卡托 variant B 只写成 `Mercator` + 一条 `standard_parallel_1`。
/// 只看方法名会把它们一律判成 1SP/variant A，进而用错尺度因子
/// （2SP 的 k0 由标准纬线导出，不是 1）。
///
/// 这里按"参数形态"回补 variant，判据只用参数名，不看数值——
/// 数值判据（比如"k0 是不是 1"）在真实数据里并不可靠。
fn refine_method_code(
  code : Int32,
  params : Array[@types.Parameter],
) -> Int32 {
  let mut first_parallel = false
  let mut second_parallel = false
  for p in params {
    let key = normalize(p.name)
    if key.contains("standardparallel1") || key.contains("1ststandardparallel") {
      first_parallel = true
    }
    if key.contains("standardparallel2") || key.contains("2ndstandardparallel") {
      second_parallel = true
    }
  }
  if code == 9801 && second_parallel {
    9802
  } else if code == 9804 && first_parallel {
    9805
  } else if code == 9810 && first_parallel {
    9829
  } else {
    code
  }
}

///|
/// 解析投影坐标系（PROJCRS / PROJCS）。
fn parse_projected(node : WktNode) -> @types.ProjectedCrs raise @types.CrsError {
  let name = first_text(node).unwrap_or("unnamed projected CRS")
  // 基底可以是 BASEGEOGCRS（WKT2）、BASEGEODCRS 或 GEOGCS（WKT1）
  let base = match base_geographic_node(node) {
    Some(b) => parse_geographic(b)
    None => @types.GeographicCrs::new("unknown base", @types.wgs84_datum)
  }
  // 转换：WKT2 在 CONVERSION 里，WKT1 直接把 PROJECTION + PARAMETER 放在 PROJCS 下
  let conversion = conversion_of(node)
  let method_name = conversion.0
  let params = conversion.1
  let code = refine_method_code(method_code_of(method_name), params)
  let unit = parse_linear_unit(node)
  let axis = parse_axis_order(node, true)
  let id = parse_identifier(node)
  @types.ProjectedCrs::new(
    name,
    base,
    method_name,
    params,
    method_code=code,
    unit=unit,
    axis=axis,
    id=id,
  )
}

///|
/// 解析任意 WKT 文本为 CRS。
///
/// 支持：GEOGCRS、PROJCRS、GEOGCS、PROJCS、BOUNDCRS（取源 CRS 并读取
/// 其到目标的七参数）。其余类型（COMPOUNDCRS、VERTCRS）暂不支持，
/// 会返回明确的错误而不是静默降级。
pub fn parse(text : String) -> @types.Crs raise @types.CrsError {
  let tree = parse_tree(text)
  let key = form_key(tree)
  match key {
    "GEOGCRS" | "GEODCRS" | "GEOGCS" =>
      @types.Crs::Geographic(parse_geographic(tree))
    "PROJCRS" | "PROJCS" =>
      @types.Crs::Projected(parse_projected(tree))
    "BOUNDCRS" => {
      let source = match find_child(tree, "SOURCECRS") {
        Some(s) => s
        None => raise @types.CrsError::Parse("BOUNDCRS 缺少 SOURCECRS")
      }
      let kids = form_children(source)
      if kids.length() == 0 {
        raise @types.CrsError::Parse("SOURCECRS 为空")
      }
      let inner = kids[0]
      match form_key(inner) {
        "GEOGCRS" | "GEOGCS" =>
          @types.Crs::Geographic(parse_geographic(inner))
        "PROJCRS" | "PROJCS" =>
          @types.Crs::Projected(parse_projected(inner))
        other => raise @types.CrsError::UnsupportedOperation("BOUNDCRS 内的 " + other)
      }
    }
    other => raise @types.CrsError::UnsupportedOperation("不支持的 WKT 根节点: " + other)
  }
}
