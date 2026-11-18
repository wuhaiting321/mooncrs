# verification：拿官方点位对账

这个目录不放产品代码，只放"证明精度"的东西。

`moon test` 里的断言验的是"实现遵循公式"，用的是记忆中的期望值；而初审要看的是
"在真实经纬度上差多少米"。两者不是一回事，所以单独放一套：

- `data/dhdn_bkg_points.csv` — 德国 BKG 官方 31 个点（成对的 DHDN / ETRS89 坐标）
- `run_verification.py` — 驱动 CLI、逐点算残差、出统计与明细
- `results/` — 每次运行的产物（已入库，便于对照历史）

完整判读见 `../docs/VERIFICATION.md`。

## 跑一遍

```bash
# 网格文件不入库（版权与体积），先取
curl -L -o docs/BETA2007.gsb \
  https://raw.githubusercontent.com/OSGeo/PROJ/master/data/tests/BETA2007.gsb

moon build --target js
python verification/run_verification.py
```

输出四个文件到 `results/`：

| 文件 | 内容 |
| --- | --- |
| `residuals_seven.csv` | 7 参数路径逐点 dx/dy/合成（米，9 位小数） |
| `residuals_grid.csv` | BETA2007 网格路径逐点残差（米，9 位小数） |
| `residuals_ed50.csv` | ED50 → ETRS89 单点 |
| `summary.json` | 中位/平均/P95/最大 |

`--no-grid` 只跑 7 参数；`--grid 路径` 指定别的网格文件。

## 数据来源与许可

| 文件 | 来源 | 说明 |
| --- | --- | --- |
| `dhdn_bkg_points.csv` | BKG（德国联邦制图与大地测量局）`BETA2007testdaten.csv` | 经 PROJ 的 `test/gie/DHDN_ETRS89.gie` 转载，数值未改动 |
| `BETA2007.gsb`（需自取） | 同上，经 PROJ `data/tests/` 分发 | 德国官方 BeTA2007 格网，82 KB |
| ED50 点（写在脚本里） | ICGC（加泰罗尼亚制图与地质研究所） | 经 PROJ 的 `test/gie/epsg_grid.gie` 转载 |

数据只用于验证，不随本库分发，也不改变本库的许可证。如需再分发网格文件，
请遵守各自发布方的条款（见 `../docs/DATA.md`）。

## 为什么网格残差接近零

BKG 的这 31 个点**同时是 BETA2007 格网的生成控制点**——它们的用途就是让各软件
核对"有没有正确读出并插值这份格网"。所以残差只有 2 µm 量级，说明的是"实现没引入
误差"（正好等于 float32 的存储量化步长），不是"格网精度是微米级"。

格网本身的绝对精度（BKG 评估 0.1 m 级）需要用独立 GNSS 点位才能验证，本库不主张
超出该标称的精度。这一点在 `../docs/VERIFICATION.md` §3.4 写得更细。

## 为什么不塞进 `moon test`

网格文件 82 KB 且不入库，塞进 CI 会让"没下载数据就跑不了测试"。现在的分工是：

- `moon test`：7 参数路径的 31 点回归（不依赖外部文件，`crs/transform_d_test.mbt`）
- 本脚本：两条路径的完整逐点对照（需要网格文件，人工跑）
