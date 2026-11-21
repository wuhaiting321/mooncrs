# mooncrs

MoonBit 从零实现的坐标参考系（CRS）转换引擎。

[![CI](https://github.com/wuhaiting321/mooncrs/actions/workflows/ci.yml/badge.svg)](https://github.com/wuhaiting321/mooncrs/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-wuhaiting321%2Fmooncrs-blue)](https://mooncakes.io/docs/wuhaiting321/mooncrs)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

- **作者**：wuhaiting321（19177746962@163.com）
- **仓库**：https://github.com/wuhaiting321/mooncrs （提交按功能模块组织，逐条可在 `git log` 中核查）
- **版本**：0.1.0 ｜ **许可**：Apache-2.0 ｜ **方向**：空间数据基础设施 / 坐标几何基础库

## 项目简介

mooncrs 是一个用 MoonBit 从零实现的坐标参考系（CRS）转换引擎：把 WKT2:2019、
WKT1、PROJ 串、EPSG 码四种定义写法统一成一个模型，在地理、投影、地心直角三类
坐标系之间互转，并把"这次转换靠不靠得住"一起交出来——能算的说清怎么算的，
算不了的说清缺什么。

难的不是套公式，是同时处理定义语法、投影算法、基准变换与单位轴序四件事。任何
一处错了程序都不会崩，只会把结果偏几十米到几百公里——比直接报错危险得多。

这个能力在 C/Python/JS 里是成熟基础设施（PROJ、pyproj、proj4js），在 MoonBit
生态中长期缺位。本项目核心包只依赖 `moonbitlang/core`，不绑 PROJ、不调 C 库、
不用 FFI，250 个 EPSG 定义编译进二进制，引擎加 CLI 编到 wasm-gc 约 165 KB。

当前规模 **12 103 行 MoonBit**（实现 9 444 + 测试 2 659），**120 个测试全部通过**；
正确性以 EPSG 官方算例为准，并用 BKG 公开发布的 31 个点位逐点对账，数字与复现
命令见 [`docs/VERIFICATION.md`](docs/VERIFICATION.md)。

## 安装

要求 MoonBit 工具链 `moonc` ≥ 0.10.16（本项目在 v0.10.16 上验证）。

作为库使用：

```bash
moon add wuhaiting321/mooncrs
```

在 `moon.pkg` 里引入需要的子包，然后 `import` 该包：

```
import {
  "wuhaiting321/mooncrs/crs",
}
```

核心包（`types` / `projection` / `wkt` / `projstr` / `epsg` / `crs` / `operation` / `grid`）
只依赖 `moonbitlang/core`；只有 CLI 为了读取 `.gsb` 用到 `moonbitlang/x` 的 `fs`。

从源码构建：

```bash
git clone https://github.com/wuhaiting321/mooncrs
cd mooncrs
moon check && moon test
moon build --target wasm-gc --release
```

## 快速开始

```moonbit
import {
  "wuhaiting321/mooncrs/crs",
}

fn main raise {
  // 四种写法都认：EPSG 码、裸码、PROJ 串、WKT
  let from = @crs.parse("EPSG:4326")
  let to = @crs.parse("+proj=utm +zone=50 +datum=WGS84")

  // 单点转换：北京 116.3912°E, 39.9075°N
  let (e, n) = @crs.transform(from, to, 116.3912, 39.9075)
  println("\{e}, \{n}")

  // 需要判断"这个结果能不能用"时，走带报告的入口
  let (_, _, report) = @crs.transform_report(from, to, 116.3912, 39.9075)
  println(report.to_text())
}
```

`transform` 只返回坐标；`transform_report` 额外给出这次用的哪条运算、标称精度、
适用范围、跳过了哪些更优方案、有哪些保留意见。**拿结果去做决定时用后者。**

完整可运行版本见 [`examples/basic`](examples/basic)。

## CLI 用法

CLI 是库之上的薄壳，用于手工核对与脚本调用：

```bash
moon run cmd/main -- <命令> [参数...]
```

| 命令 | 作用 |
| --- | --- |
| `transform [--grid ID=PATH] [--explain] <源> <目标> <x> <y>` | 坐标转换；`--explain` 打印运算、方法、精度、范围、警告 |
| `ops --from <源> --to <目标> [--point <x> <y>]` | 列出该对基准的**全部候选运算**与逐条适用性 |
| `grid <文件.gsb> [<lon> <lat>]` | 查看网格覆盖范围与单点改正量 |
| `describe <CRS>` | 人类可读的坐标系说明 |
| `wkt <CRS>` / `proj <CRS>` | 输出 WKT2 / PROJ 串 |
| `list [起始] [结束]` / `search <关键词>` | 浏览内置的 250 个 EPSG 码 |
| `version` | 版本号 |

CRS 参数接受四种写法：`EPSG:4326`、裸码 `32650`、`+proj=utm +zone=50 +datum=WGS84`、
WKT2/WKT1 文本（含空格时加引号）。退出码：`0` 成功 / `1` 参数错误 / `2` 可恢复错误。

## 示例

```bash
# 库 API：解析 → 转换 → 读报告
moon run examples/basic

# CLI：最常用的五条命令
bash examples/cli.sh
```

## 复现与测试

```bash
moon check --deny-warn     # 0 error 0 warning
moon test                  # 120 / 120
moon run cmd/main -- transform --explain EPSG:4277 EPSG:4258 1.7179 52.6576
```

CI（`.github/workflows/ci.yml`）在每次 push 上跑同一组步骤：检查、测试、wasm-gc 与
native 构建、体积上限、退出码、解释输出契约、示例。

精度不是靠公式算例声明的。`docs/VERIFICATION.md` 给出 BKG 31 个官方点位的逐点残差、
数据出处与复现命令；`docs/DATA.md` 说明高精度网格如何获取与校验。

## 项目方向与通用性说明

项目方向属于**开发者基础设施**，具体是空间数据栈最底层的坐标几何能力：只要涉及
位置，就必然有一次坐标转换；这个能力缺失时，整条技术栈无法只用 MoonBit 建成。

通用性体现在四个维度，任何一维收窄都会让库退化成一次性脚本：

- **坐标系类型**：地理坐标系、投影坐标系、地心直角坐标系三类两两互通
- **定义格式**：WKT2:2019 / WKT1(OGC 01-009) / PROJ 串 / EPSG 码，四种自动判别
- **地域覆盖**：全球（含极区、南半球、跨 180° 经线）与地方坐标系（英、瑞、比、波、中、北美）
- **运行环境**：核心包不接触 IO，wasm、wasm-gc、js、native 四目标均构建通过（native 在 Linux CI 上构建并运行验证；Windows 本地需宿主安装 MSVC 工具链）

API 只认坐标系定义、不认业务语义，因此同一个 `transform(from, to, x, y)`
既服务地图前端，也服务测量内业、遥感预处理和批量数据管道。

## 预期使用场景

### 场景一：浏览器端 GNSS 轨迹叠加

设备管理后台要在网页地图上画车辆轨迹。设备给的是 WGS84 经纬度，瓦片底图用
Web Mercator（EPSG:3857）或某个 UTM 带。

```moonbit
let from = @crs.parse("EPSG:4326")
let to = @crs.parse("EPSG:3857")
// 同一对 CRS 只构造一次投影器，避免逐点重复初始化
let xy = @crs.transform_many(from, to, points)
```

输出等长的平面坐标数组，可直接喂给 Canvas / WebGL。过去这条链路必须引 proj4js
（约 200 KB）或回后端算；本项目编到 wasm-gc 约 165 KB，无 FFI、基础转换不需要
任何数据文件，
且 `EPSG:4326`、`+proj=utm +zone=50`、`.prj` 里的 WKT 三种写法可混用，
数据源不统一时不必写适配层。

### 场景二：工程测量的跨基准坐标核对（**不适用于放样与地籍**）

设计图纸用 British National Grid（EPSG:27700，OSGB36 基准），现场 RTK 输出
WGS84 经纬度。两者不只投影不同，**基准也不同**（Airy 1830 椭球 vs WGS84 椭球），
直接套投影公式会偏一百多米。

```bash
# 七参数路径（英国境内约 2 m 级）：零数据文件
$ moon run cmd/main -- transform EPSG:4326 EPSG:27700 -1.7160 52.6579
# 网格路径（0.1 m 级）：自备 OSTN15 的 .gsb
$ moon run cmd/main -- transform --grid OSTN15_NTv2_OSGBtoETRS.gsb EPSG:4326 EPSG:27700 -1.7160 52.6579
```

内部走六步管道：换轴换单位 → 反算本基准大地坐标 → 加子午线偏移 → **按注册表选
一条带适用范围与标称精度的坐标运算**（七参数或 NTv2 网格）→ 扣目标子午线偏移 →
正算。

这是"错得最隐蔽"的场景：七参数漏了、旋转约定（EPSG 9606/9607）搞反了、椭球用错
了，或者该用网格却用了七参数，结果都仍然"看起来正常"，只是整体偏几十米到几百米。
本项目对两种旋转约定各有独立测试，并用 EPSG 官方算例逐位校验。

加上 `--explain` 会把这次的选择摊开：用了哪条运算、标称精度多少、范围在哪、有没有
因为缺文件跳过了更精确的方案。

```bash
$ moon run cmd/main -- transform --explain EPSG:4277 EPSG:4258 1.7179 52.6576
1.7160303624906261 52.65800829473848
运算    LOCAL:OSGB36_ETRS89_7P  OSGB36 → ETRS89（7 参数）
方法    七参数（位置向量）（EPSG 9606）
精度    2 m
范围    [49, -9] .. [61, 2]
出处    PROJ datum table: osgb36
说明    与 OSGB36→WGS84 同一套参数，经 WGS84/ETRS89 重合关系转达
步骤
        · 入参换轴换单位 → OSGB36 上的大地坐标
        · 坐标运算 LOCAL:OSGB36_ETRS89_7P（七参数（位置向量））
        · 正算到 ETRS89 并换算单位
已跳过
        · EPSG:7709（0.1 m）更精确，但需要网格文件 OSTN15_NTv2_OSGBtoETRS.gsb；
          当前未加载，用 --grid 指定文件，索取方式见 docs/DATA.md
警告    无
```

如果关心"有没有更准的路、为什么没用上"，用 `ops` 把整张清单摊开——它和转换
走的是同一份候选列表（`crs/candidates.mbt`），不会出现"命令行说有三条、
转换却走了第四条"：

```bash
$ moon run cmd/main -- ops --from EPSG:4277 --to EPSG:4258 --point 1.7179 52.6576
源      EPSG:4277  OSGB36
目标    EPSG:4258  ETRS89
点      1.7179, 52.6576

  EPSG:7709  OSGB36 → ETRS89（OSTN15 网格）  NTv2 网格改正  精度 0.1 m  [缺数据] ...
  LOCAL:OSGB36_ETRS89_7P  OSGB36 → ETRS89（7 参数）  七参数（位置向量）  精度 2 m  [适用于该点]

共 2 条候选，其中 1 条在当前条件下可用
```

**同一套方法在德国场地上做过逐点验证**：31 个 BKG 官方点，七参数中位 0.76 m、
最大 2.55 m；换成 BETA2007 网格后 2 µm。这条实验说明精度差异来自**数据**而不是
算法——也正是"一套七参数走天下"站不住的原因。

**边界要说清楚：本库不承担放样、地籍与成果提交所需的精度担保。** 放样精度来自
现场控制点联测与本地校准，不来自基准转换；即便最好的公开网格（OSTN15）也带 0.1 m
标称误差，而放样要厘米级。本库能做的是"把坐标换到同一套基准上，并说清这次用了
哪条运算、精度多少、数据覆盖到哪"。完整的判据与不支持清单见
[`docs/ACCURACY.md`](docs/ACCURACY.md)。

### 场景三：多源空间数据 ETL

数据管道要把三批数据合并：Shapefile（`.prj` 是 WKT1，常带"美国测量英尺"）、
GeoJSON（WGS84 经纬度）、数据库里的 EPSG 码。三者写法不同、单位不同、轴序不同。

```moonbit
let a = @crs.parse("EPSG:32040")                     // 注册表引用
let b = @crs.parse("+proj=lcc +lat_1=28.38 ...")     // PROJ 串
let c = @crs.parse("PROJCS[\"NAD27 / Texas ...\"]")  // WKT1（.prj）
let out = @crs.transform(c, @crs.parse("EPSG:4326"), e, n)
```

坑集中在单位：EPSG 里德州南中的假东是 2000000 **美国测量英尺**
（0.3048006096012192 m，与国际英尺差 2 ppm），当米处理结果会偏 5.7 倍。
本项目把换算做在语义层，并有专门测试守这个算例；WKT1 没有 variant 概念，
`Lambert_Conformal_Conic` 配两条 `standard_parallel_*` 实际是 2SP，
只看方法名会误判成 1SP，本项目按参数形态回补方法码。

## 核心功能规划

以下能力均已完成，可执行 `moon check` / `moon test` 直接复核。

- 提供四种坐标系定义格式的统一解析与自动判别：WKT2:2019、WKT1、PROJ 串、EPSG 码
- 提供 WKT 双括号兼容（`[ ]` 与 `( )`），可直接读取 Shapefile 的 `.prj`
- 提供 12 种投影方法的正算与反算，覆盖 EPSG 方法码 9801/9802/9804/9805/9806/9807/9810/9815/9820/9822/9829/1024
- 提供 Helmert 七参数基准变换，同时支持 EPSG 9606（Position Vector）与 9607（Coordinate Frame）两种旋转约定
- 提供坐标运算注册表：一对基准可登记多条运算（适用范围、标称精度、出处），按"精度 → 范围 → 标识"三层排序选取，结果确定可复现
- 提供严格模式：无可用运算、或点落在运算适用范围外时一律报错，并说明缺哪个文件、范围在哪；降级只能走显式的 `transform_ballpark`
- 提供 `TransformationReport`：每次转换可取出用了哪条运算、方法、精度、范围、跳过哪些更优方案、有哪些保留
- 提供 NTv2（`.gsb`）网格改正：解析文件头与子网格、双线性插值、反解迭代、内外边界判定；`grid` 子命令可先查覆盖范围再决定是否使用
- 提供大地坐标与地心直角坐标（ECEF）的双向转换
- 提供单位与轴序归一：度/弧度/百分度，米/公里/国际英尺/美国测量英尺，经纬↔纬经
- 提供本初子午线偏移支持（巴黎、布鲁塞尔、费罗、雅加达等）
- 内置 250 个 EPSG 码注册表，其中 UTM 与 CGCS2000 三度带按编号规则生成而非手抄
- 提供 `Crs → WKT2` 与 `Crs → PROJ 串` 的反向生成，支持四种格式互转
- 提供固定六步转换管道，以及 `transform` / `transform_3d` / `transform_many` 三个入口
- 提供 31 个官方点位的逐点残差验证（`docs/VERIFICATION.md`），数据出处、原始输出与复现命令齐全
- 提供 `--explain`：每次转换打印所用运算、方法、标称精度、适用范围、跳过的更优路径与警告
- 提供 `ops` 子命令：转换之前先列出该基准对的**全部候选**，按精度排序，逐条标「适用于该点 / 超出范围 / 缺数据」并说明原因；与转换共用同一份候选清单，不会各说各话
- 提供 6 类显式错误（Parse / Invalid / UnsupportedProjection / UnsupportedOperation / NotFound / Domain），全部 `raise`，不做静默降级
- 提供 CLI 九条子命令：`transform` / `ops` / `grid` / `describe` / `wkt` / `proj` / `list` / `search` / `version`；退出码 0/1/2 分别表示成功、参数错、可恢复错误
- 提供 wasm、wasm-gc、js、native 四目标构建，CI 自动验证 wasm-gc 与 native，wasm-gc 产物约 165 KB（CI 里设 170 KB 上限，超了就失败）
- 提供 120 个自动化测试，覆盖 EPSG 官方案例、12 种投影闭环、跨基准往返、数学性质（Albers 等积性、Helmert 双约定）、31 个官方点位的残差回归，以及"该失败时必须失败"的反例（范围外、缺数据、坏网格文件）

## 能力边界

这一节是上一版被驳回的直接产物。初审意见指出「任意跨基准精确转换」「工程放样」
两类表述没有证据支撑，本版把它们换成了下面这张表——能做什么、做到什么程度、
依据在哪，逐行可查。

| 场景 | 能做到 | 做不到 / 不承诺 | 依据 |
| --- | --- | --- | --- |
| 同基准、仅投影或单位不同 | 数学闭合（往返误差 < 1 mm） | — | 12 种投影的闭环测试 |
| 跨基准、有登记运算 | 按点选运算，给出标称精度 | 不保证达到该精度，只声明量级 | 注册表 `accuracy_m` + 官方点位验证 |
| 跨基准、无登记运算 | **显式报错**，说明缺哪条运算 | 不静默返回原值、不自动降级 | `UnsupportedOperation` + 反例测试 |
| 点落在运算范围外 | **显式报错**，给出该运算的适用范围 | 不外推、不"就近取一个" | 范围判定测试（角内/边界/角外） |
| 需要网格但缺 `.gsb` | 跳过该候选并在报告里写明缺哪个文件 | 不假装用七参数"差不多" | `--explain` 的「已跳过」段 |
| 定义文本自带 `TOWGS84` | 采用，但标注"无范围、无精度" | 不当作可信参数 | 报告 `警告` 段 |
| 米级 GIS 入库、图纸对位 | 七参数 1–3 m 或网格 0.1 m 级 | — | BKG 31 点残差 |
| 工程放样、地籍测量 | 把坐标换到同一基准上 | **不承诺厘米级**；精度须来自现场控制点联测与本地校准 | `docs/ACCURACY.md` §1 |
| 成果提交、面积量算 | 提供运算与精度信息 | 不承担精度担保 | `docs/ACCURACY.md` §2 |

### 不支持清单

明确列出不做的事，比含糊其辞更有用——用户至少知道该去哪找替代方案。

| 不支持 | 说明 |
| --- | --- |
| 垂直基准与大地水准面模型（EGM96/EGM2008） | 高程只做搬运，不做基准改正 |
| 14 参数时间相关变换（ITRF 历元转换） | 需要速度场与历元，本版不做；报告会提示"历元未声明" |
| NADCON 的 `.las` / `.los` 网格 | 格式未实现；遇到时明确报"格式未实现"，不伪装成"缺数据" |
| NTv1（`.dat`）、大端 `.gsb` | NTv1 是另一种布局；大端文件需先转小端 |
| Xian 1980 / Beijing 1954 等未登记基准 | 注册表里没有带出处的参数，转换显式报错。**不虚构参数** |
| 多跳串联（A→B→C 自动拼接） | 每一跳都会引入误差且难以在报告里交代；需要时请显式分两步 |
| 厘米级放样、地籍、成果提交的精度担保 | 见上表 |

## 原创与参考说明

- **是否移植项目**：否
- **原项目名称**：无（本项目为原创实现，无上游仓库、无逐行翻译的对应实现）
- **本项目许可证**：Apache License 2.0

实现过程中参考的公开规范与文献（均为公式与语法标准，未复制任何第三方源码）：

| 资料 | 用途 | 版权 / 许可证 |
| --- | --- | --- |
| Snyder, *Map Projections: A Working Manual*（USGS PP 1395, 1987） | 投影公式 | 美国政府出版物，公有领域 |
| EPSG Guidance Note 7-2 | 方法定义、参数语义、方法码 | IOGP 发布，允许在软件中引用 |
| OGC 18-010r7（WKT2:2019）、OGC 01-009（WKT1） | 语法规范 | OGC 文档许可 |
| EPSG 公开数据集 | 250 个码的参数值 | 允许在软件中引用 |
| PROJ 文档 | 仅参考 `+proj` 关键字的行为语义与命名习惯 | MIT，未读取或复制其源码 |

区分"原创"与"移植"的标准不是公式是否自创（公式是公开数学，任何实现都会长得像），
而是代码是否自写、结构是否自设计。本项目的分层（types / projection / wkt /
projstr / epsg / crs）与六步管道是为 MoonBit 的类型系统和错误模型重新设计的，
与 PROJ 的 `PJ` 结构体加运算链表架构没有对应关系。依赖情况：核心包外部依赖为 0；
CLI 为读取 `.gsb` 使用官方扩展库 `moonbitlang/x` 的 `fs` 包（版本的锁定写在 `moon.mod`）；
仓库内不含任何第三方网格数据。

## 许可证

Apache License 2.0（见 [LICENSE](LICENSE)）。
