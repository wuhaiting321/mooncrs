#!/usr/bin/env bash
# CLI 最常用的几条命令。在仓库根目录运行：bash examples/cli.sh
set -euo pipefail
cd "$(dirname "$0")/.."

run() {
  echo "\$ mooncrs $*"
  moon run cmd/main -- "$@"
  echo
}

# 1) 版本
run version

# 2) 同基准、仅投影不同：WGS84 经纬度 -> UTM 50N
run transform EPSG:4326 EPSG:32650 116.3912 39.9075

# 3) 跨基准：OSGB36 -> ETRS89，并解释用了哪条运算
run transform --explain EPSG:4277 EPSG:4258 1.7179 52.6576

# 4) 转换之前先看全部候选：哪条更准、哪条缺数据
run ops --from EPSG:4277 --to EPSG:4258 --point 1.7179 52.6576

# 5) 查看定义与反向生成
run describe 27700
run wkt 4326
