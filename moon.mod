// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "wuhaiting321/mooncrs"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/wuhaiting321/mooncrs"

license = "Apache-2.0"

keywords = [
  "crs",
  "gis",
  "epsg",
  "wkt",
  "projection",
  "coordinate",
  "geodesy",
]

preferred_target = "wasm"

import {
  "moonbitlang/x@0.4.48"
}

description = "Coordinate reference system transformation engine: WKT2/WKT1/PROJ/EPSG in, 12 projections, datum operations carrying accuracy and area of use."
