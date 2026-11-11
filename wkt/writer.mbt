// WKT2:2019 序列化。
//
// 目的有两个：① 让用户能把解析结果再吐出去做比对（往返一致性测试靠它）；
// ② 让 CLI 的 `describe` 命令输出可读、可被 QGIS / PROJ 直接吃进去的定义。
// 不做"最短 WKT"优化，宁可多写全称，可读性优先。

///|
/// 把 CRS 序列化成 WKT2 文本。
pub fn to_wkt2(crs : @types.Crs) -> String {
  match crs {
    @types.Crs::Geographic(g) => geographic_to_wkt(g, 0)
    @types.Crs::Projected(p) => projected_to_wkt(p, 0)
    @types.Crs::Geocentric(c) => geocentric_to_wkt(c)
  }
}

///|
/// 生成缩进。
fn indent(level : Int) -> String {
  let sb = StringBuilder()
  for _ in 0..<level {
    sb.write_string("  ")
  }
  sb.to_string()
}

///|
/// 数值格式化。整数不带小数点，与 EPSG 官方导出保持一致。
fn fmt(v : Double) -> String {
  if v == v.round() && v.abs() < 1.0e15 {
    v.to_string()
  } else {
    v.to_string()
  }
}

///|
/// 字符串字面量加引号；内部双引号按 WKT 规则转义成两个双引号。
fn quote(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for ch in s {
    if ch == '"' {
      sb.write_string("\"\"")
    } else {
      sb.write_char(ch)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
/// 椭球片段。
fn ellipsoid_wkt(e : @types.Ellipsoid, level : Int) -> String {
  indent(level) +
  "ELLIPSOID[" +
  quote(e.name) +
  "," +
  fmt(e.semi_major) +
  "," +
  fmt(e.inverse_flattening) +
  ",\n" +
  indent(level + 1) +
  "LENGTHUNIT[\"metre\",1]]"
}

///|
/// 基准片段。
fn datum_wkt(d : @types.Datum, level : Int) -> String {
  let sb = StringBuilder()
  sb.write_string(indent(level))
  sb.write_string("DATUM[")
  sb.write_string(quote(d.name))
  sb.write_string(",\n")
  sb.write_string(ellipsoid_wkt(d.ellipsoid, level + 1))
  sb.write_string("]")
  sb.to_string()
}

///|
/// 本初子午线片段。非格林尼治时用 DMS 形式的数值。
fn primem_wkt(pm : Double, level : Int) -> String {
  let name = if pm == 0.0 { "Greenwich" } else { "Reference meridian" }
  indent(level) +
  "PRIMEM[" +
  quote(name) +
  "," +
  fmt(pm) +
  ",\n" +
  indent(level + 1) +
  "ANGLEUNIT[\"degree\",0.0174532925199433]]"
}

///|
/// 地理坐标系 → WKT2。
fn geographic_to_wkt(g : @types.GeographicCrs, level : Int) -> String {
  let sb = StringBuilder()
  sb.write_string(indent(level))
  sb.write_string("GEOGCRS[")
  sb.write_string(quote(g.name))
  sb.write_string(",\n")
  sb.write_string(datum_wkt(g.datum, level + 1))
  sb.write_string(",\n")
  sb.write_string(primem_wkt(g.datum.prime_meridian, level + 1))
  sb.write_string(",\n")
  sb.write_string(indent(level + 1))
  sb.write_string("CS[ellipsoidal,2],\n")
  match g.axis {
    LatLon => {
      sb.write_string(indent(level + 1))
      sb.write_string("AXIS[\"latitude\",north,ORDER[1]],\n")
      sb.write_string(indent(level + 1))
      sb.write_string("AXIS[\"longitude\",east,ORDER[2]],\n")
    }
    _ => {
      sb.write_string(indent(level + 1))
      sb.write_string("AXIS[\"longitude\",east,ORDER[1]],\n")
      sb.write_string(indent(level + 1))
      sb.write_string("AXIS[\"latitude\",north,ORDER[2]],\n")
    }
  }
  sb.write_string(indent(level + 1))
  sb.write_string("ANGLEUNIT[")
  sb.write_string(quote(g.unit.name))
  sb.write_string(",")
  sb.write_string(fmt(g.unit.factor))
  sb.write_string("]")
  match g.id {
    Some(id) => {
      sb.write_string(",\n")
      sb.write_string(indent(level + 1))
      sb.write_string("ID[")
      sb.write_string(quote(id.authority))
      sb.write_string(",")
      sb.write_string(id.code.to_string())
      sb.write_string("]")
    }
    None => ()
  }
  sb.write_string("]")
  sb.to_string()
}

///|
/// EPSG 方法码 → WKT2 方法名。未收录的方法沿用原始名称。
pub fn method_name_of(code : Int32, fallback : String) -> String {
  match code {
    9807 => "Transverse Mercator"
    9804 => "Mercator (variant A)"
    9805 => "Mercator (variant B)"
    1024 => "Popular Visualisation Pseudo Mercator"
    9801 => "Lambert Conic Conformal (1SP)"
    9802 => "Lambert Conic Conformal (2SP)"
    9822 => "Albers Equal Area"
    9815 => "Hotine Oblique Mercator (variant B)"
    9810 => "Polar Stereographic (variant A)"
    9829 => "Polar Stereographic (variant B)"
    9806 => "Cassini-Soldner"
    9820 => "Lambert Azimuthal Equal Area"
    _ => fallback
  }
}

///|
/// 判断参数应按角度还是长度序列化。
///
/// 依据 EPSG 参数码判断最可靠；参数码缺失时退回按名称猜。
fn parameter_unit_wkt(p : @types.Parameter, level : Int) -> String {
  let angle_codes : Array[Int32] = [
    8801, 8802, 8811, 8812, 8813, 8814, 8815, 8821, 8822, 8823, 8824, 8826, 8827,
    8832, 8833,
  ]
  let is_angle = angle_codes.contains(p.code) || p.unit.contains("degree") ||
    p.unit.contains("radian") || p.unit.contains("grad")
  if is_angle {
    indent(level) + "ANGLEUNIT[\"degree\",0.0174532925199433]"
  } else if p.unit.contains("unity") || p.code == 8805 || p.code == 8815 {
    indent(level) + "SCALEUNIT[\"unity\",1]"
  } else {
    indent(level) + "LENGTHUNIT[\"metre\",1]"
  }
}

///|
/// 参数片段。
fn parameter_wkt(p : @types.Parameter, level : Int) -> String {
  let sb = StringBuilder()
  sb.write_string(indent(level))
  sb.write_string("PARAMETER[")
  sb.write_string(quote(p.name))
  sb.write_string(",")
  sb.write_string(fmt(p.value))
  sb.write_string(",\n")
  sb.write_string(parameter_unit_wkt(p, level + 1))
  if p.code != 0 {
    sb.write_string(",\n")
    sb.write_string(indent(level + 1))
    sb.write_string("ID[\"EPSG\",")
    sb.write_string(p.code.to_string())
    sb.write_string("]")
  }
  sb.write_string("]")
  sb.to_string()
}

///|
/// 投影坐标系 → WKT2。
fn projected_to_wkt(p : @types.ProjectedCrs, level : Int) -> String {
  let sb = StringBuilder()
  sb.write_string(indent(level))
  sb.write_string("PROJCRS[")
  sb.write_string(quote(p.name))
  sb.write_string(",\n")
  sb.write_string(indent(level + 1))
  sb.write_string("BASEGEOGCRS[")
  sb.write_string(quote(p.base.name))
  sb.write_string(",\n")
  sb.write_string(datum_wkt(p.base.datum, level + 2))
  sb.write_string(",\n")
  sb.write_string(primem_wkt(p.base.datum.prime_meridian, level + 2))
  sb.write_string("],\n")
  sb.write_string(indent(level + 1))
  sb.write_string("CONVERSION[")
  sb.write_string(quote(p.name))
  sb.write_string(",\n")
  sb.write_string(indent(level + 2))
  sb.write_string("METHOD[")
  sb.write_string(quote(method_name_of(p.method_code, p.method_name)))
  if p.method_code != 0 {
    sb.write_string(",ID[\"EPSG\",")
    sb.write_string(p.method_code.to_string())
    sb.write_string("]")
  }
  sb.write_string("]")
  for param in p.params {
    sb.write_string(",\n")
    sb.write_string(parameter_wkt(param, level + 2))
  }
  sb.write_string("],\n")
  sb.write_string(indent(level + 1))
  sb.write_string("CS[Cartesian,2],\n")
  match p.axis {
    NorthEast => {
      sb.write_string(indent(level + 1))
      sb.write_string("AXIS[\"northing\",north,ORDER[1]],\n")
      sb.write_string(indent(level + 1))
      sb.write_string("AXIS[\"easting\",east,ORDER[2]],\n")
    }
    _ => {
      sb.write_string(indent(level + 1))
      sb.write_string("AXIS[\"easting\",east,ORDER[1]],\n")
      sb.write_string(indent(level + 1))
      sb.write_string("AXIS[\"northing\",north,ORDER[2]],\n")
    }
  }
  sb.write_string(indent(level + 1))
  sb.write_string("LENGTHUNIT[")
  sb.write_string(quote(p.unit.name))
  sb.write_string(",")
  sb.write_string(fmt(p.unit.factor))
  sb.write_string("]")
  match p.id {
    Some(id) => {
      sb.write_string(",\n")
      sb.write_string(indent(level + 1))
      sb.write_string("ID[")
      sb.write_string(quote(id.authority))
      sb.write_string(",")
      sb.write_string(id.code.to_string())
      sb.write_string("]")
    }
    None => ()
  }
  sb.write_string("]")
  sb.to_string()
}

///|
/// 地心坐标系 → WKT2。
fn geocentric_to_wkt(c : @types.GeocentricCrs) -> String {
  let sb = StringBuilder()
  sb.write_string("GEOCCS[")
  sb.write_string(quote(c.name))
  sb.write_string(",\n")
  sb.write_string(datum_wkt(c.datum, 1))
  sb.write_string(",\n")
  sb.write_string(primem_wkt(c.datum.prime_meridian, 1))
  sb.write_string(",\n")
  sb.write_string("  LENGTHUNIT[")
  sb.write_string(quote(c.unit.name))
  sb.write_string(",")
  sb.write_string(fmt(c.unit.factor))
  sb.write_string("]]")
  sb.to_string()
}
