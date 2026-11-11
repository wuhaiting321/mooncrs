// CRS 的文本描述。
//
// 用途有两个：CLI 的 `describe` 子命令，以及出错时的上下文。
// 因此输出必须是"人能直接读懂"的，而不是 `ProjectedCrs { .. }` 这种
// 调试转储——后者的信息密度高但对人不友好，只在 `--debug` 时用。

///|
/// 生成多行描述。
pub fn describe(crs : @types.Crs) -> String {
  let sb = StringBuilder()
  sb.write_string(crs.name())
  sb.write_string("\n")
  match crs.identifier() {
    Some(id) => {
      sb.write_string("  标识      " + id.to_text() + "\n")
    }
    None => ()
  }
  sb.write_string("  类型      " + kind_text(crs) + "\n")
  match crs {
    Geographic(g) => {
      write_datum(sb, g.datum)
      sb.write_string("  单位      " + g.unit.name + "（1 " + g.unit.name + " = " + @projstr.fmt(g.unit.factor) + " rad）\n")
      sb.write_string("  轴序      " + axis_text(g.axis) + "\n")
    }
    Projected(p) => {
      write_datum(sb, p.base.datum)
      sb.write_string(
        "  方法      " +
        p.method_name +
        "（EPSG " +
        (if p.method_code == 0 {
          "方法码未知"
        } else {
          p.method_code.to_string()
        }) +
        "）\n",
      )
      sb.write_string("  参数\n")
      for param in p.params {
        let unit = if param.unit.length() == 0 {
          ""
        } else {
          " " + param.unit
        }
        let code = if param.code == 0 {
          ""
        } else {
          "（EPSG " + param.code.to_string() + "）"
        }
        sb.write_string(
          "            " +
          param.name +
          " = " +
          @projstr.fmt(param.value) +
          unit +
          code +
          "\n",
        )
      }
      sb.write_string(
        "  单位      " +
        p.unit.name +
        "（1 " +
        p.unit.name +
        " = " +
        @projstr.fmt(p.unit.factor) +
        " m）\n",
      )
      sb.write_string("  轴序      " + axis_text(p.axis) + "\n")
    }
    Geocentric(c) => {
      write_datum(sb, c.datum)
      sb.write_string("  单位      " + c.unit.name + "\n")
      sb.write_string("  轴序      X, Y, Z（地心直角）\n")
    }
  }
  sb.to_string()
}

///|
/// 基准与椭球信息。
fn write_datum(sb : StringBuilder, datum : @types.Datum) -> Unit {
  sb.write_string("  基准      " + datum.name + "\n")
  sb.write_string(
    "  椭球      " +
    datum.ellipsoid.name +
    "（a = " +
    @projstr.fmt(datum.ellipsoid.semi_major) +
    " m，1/f = " +
    @projstr.fmt(datum.ellipsoid.inverse_flattening) +
    "）\n",
  )
  if datum.prime_meridian != 0.0 {
    sb.write_string(
      "  本初子午线 " + @projstr.fmt(datum.prime_meridian) + "°（相对格林尼治）\n",
    )
  }
  match datum.to_wgs84 {
    Some(h) =>
      if !h.is_identity() {
        sb.write_string(
          "  七参数    dx=" +
          @projstr.fmt(h.dx) +
          " dy=" +
          @projstr.fmt(h.dy) +
          " dz=" +
          @projstr.fmt(h.dz) +
          " rx=" +
          @projstr.fmt(h.rx) +
          " ry=" +
          @projstr.fmt(h.ry) +
          " rz=" +
          @projstr.fmt(h.rz) +
          " ds=" +
          @projstr.fmt(h.ds) +
          " ppm\n",
        )
      }
    None => ()
  }
}

///|
/// 坐标系类型中文名。
fn kind_text(crs : @types.Crs) -> String {
  match crs {
    Geographic(_) => "地理坐标系（经纬度）"
    Projected(_) => "投影坐标系（平面）"
    Geocentric(_) => "地心坐标系（ECEF）"
  }
}

///|
/// 轴序可读名。
pub fn axis_text(order : @types.AxisOrder) -> String {
  match order {
    LonLat => "经度, 纬度（LonLat）"
    LatLon => "纬度, 经度（LatLon，EPSG 地理坐标系官方顺序）"
    EastNorth => "东坐标, 北坐标（EastNorth）"
    NorthEast => "北坐标, 东坐标（NorthEast）"
  }
}

///|
/// 两个 CRS 的基准是否等价（椭球与本初子午线均相同）。
///
/// 只比较"是否同一基准"，不做七参数数值比较：同一基准在不同来源下
/// 可能给出精度不同的七参数（例如 OSGB36 有 7 参数与 15 参数两版），
/// 但它们仍是同一个基准。
pub fn same_datum(a : @types.Crs, b : @types.Crs) -> Bool {
  let da = a.datum()
  let db = b.datum()
  da.ellipsoid.semi_major == db.ellipsoid.semi_major &&
  da.ellipsoid.inverse_flattening == db.ellipsoid.inverse_flattening &&
  da.prime_meridian == db.prime_meridian
}
