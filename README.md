# mooncrs 项目申报书

> 2026 MoonBit Hackathon · 11 月赛

## 基本信息

- **项目名称**：mooncrs — MoonBit 坐标参考系转换引擎
- **项目作者**：wuhaiting321
- **联系方式**：19177746962@163.com
- **GitHub 仓库链接**：https://github.com/wuhaiting321/mooncrs
- **项目方向**：空间数据基础设施 / 坐标几何基础库
- **是否为移植项目**：否，原创项目

## 项目简介

mooncrs 是一个用 MoonBit 从零实现的坐标参考系（CRS）转换引擎。它把真实世界里
四种坐标系定义写法——WKT2:2019、WKT1、PROJ 串、EPSG 码——统一成一个模型，
再完成任意两种坐标系之间的精确转换。

这件事看起来只是"把经纬度换成平面坐标"，实际要同时处理四件事：**定义语法**、
**投影算法**、**基准变换**（不同椭球之间的七参数）、以及**单位与轴序**
（度/弧度/英尺、经纬 vs 纬经）。任何一处错了，程序不会崩，只会把结果偏移
几十米到几百公里——比直接报错危险得多。

这个能力在 C/Python/JS 里都是成熟的基础设施（PROJ、pyproj、proj4js），但在
MoonBit 生态中长期缺位。截至 2026-11，在 mooncakes.io、GitHub
（`moonbit + crs/epsg/proj`）等可检索范围内，未发现可直接复用的 CRS 引擎。
本项目把它补齐，并刻意选择"零外部依赖、零数据文件"的路线：不绑定 PROJ、
不调用 C 库、不用 FFI，只依赖 `moonbitlang/core` 的 `math` / `env` / `debug`，
250 个 EPSG 定义编译进二进制，整个引擎加 CLI 编译为 **113 KB** 的 wasm-gc 模块，
可直接分发到浏览器与边缘函数。

当前规模：**7 148 行 MoonBit**（实现 5 960 + 测试 1 188），**62 个测试全部通过**，
`moon check` 零错误零告警。正确性以 EPSG 官方公布算例为准（英国国家格网
E 651409.903 / N 313177.270、NAD27 德州南中 2963503.91 / 254759.80 美测尺、
Web Mercator 世界宽度 20037508.342789244 m），均命中到厘米级以内，另用 Python
独立复算排除"测试与实现犯同一个错"。

## 项目方向与通用性说明

项目方向属于**开发者基础设施**，具体是空间数据栈最底层的坐标几何能力：只要涉及
位置，就必然有一次坐标转换；这个能力缺失时，整条技术栈无法只用 MoonBit 建成。

通用性体现在四个维度，任何一维收窄都会让库退化成一次性脚本：

- **坐标系类型**：地理坐标系、投影坐标系、地心直角坐标系三类两两互通
- **定义格式**：WKT2:2019 / WKT1(OGC 01-009) / PROJ 串 / EPSG 码，四种自动判别
- **地域覆盖**：全球（含极区、南半球、跨 180° 经线）与地方坐标系（英、瑞、比、波、中、北美）
- **运行环境**：核心包不接触 IO，同一份代码可编到 wasm、wasm-gc、js、native

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
（约 200 KB）或回后端算；本项目编到 wasm-gc 只有 113 KB，无 FFI、无数据文件，
且 `EPSG:4326`、`+proj=utm +zone=50`、`.prj` 里的 WKT 三种写法可混用，
数据源不统一时不必写适配层。

### 场景二：工程测量与跨基准放样

设计图纸用 British National Grid（EPSG:27700，OSGB36 基准），现场 RTK 输出
WGS84 经纬度。两者不只投影不同，**基准也不同**（Airy 1830 椭球 vs WGS84 椭球），
直接套投影公式会偏一百多米。

```bash
$ moon run cmd/main -- transform EPSG:4326 EPSG:27700 -1.7160 52.6579
```

内部走完整六步管道：换轴换单位 → 反算本基准大地坐标 → 加子午线偏移 →
Helmert 七参数（经地心 WGS84）→ 扣目标子午线偏移 → 正算。

这是"错得最隐蔽"的场景：七参数漏了、旋转约定（EPSG 9606/9607）搞反了、或椭球
用错了，结果都仍然"看起来正常"，只是整体偏几十到几百米。本项目对两种旋转约定
各有独立测试，并用 EPSG 官方算例逐位校验。

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
- 提供大地坐标与地心直角坐标（ECEF）的双向转换
- 提供单位与轴序归一：度/弧度/百分度，米/公里/国际英尺/美国测量英尺，经纬↔纬经
- 提供本初子午线偏移支持（巴黎、布鲁塞尔、费罗、雅加达等）
- 内置 250 个 EPSG 码注册表，其中 UTM 与 CGCS2000 三度带按编号规则生成而非手抄
- 提供 `Crs → WKT2` 与 `Crs → PROJ 串` 的反向生成，支持四种格式互转
- 提供固定六步转换管道，以及 `transform` / `transform_3d` / `transform_many` 三个入口
- 提供 6 类显式错误（Parse / Invalid / UnsupportedProjection / UnsupportedOperation / NotFound / Domain），全部 `raise`，不做静默降级
- 提供 CLI 六条子命令：`transform` / `describe` / `wkt` / `proj` / `list` / `search`
- 提供 wasm、wasm-gc、js、native 四目标构建，wasm-gc 产物 113 KB（115 387 字节）
- 提供 62 个自动化测试，覆盖 EPSG 官方案例、12 种投影闭环、跨基准往返与数学性质（Albers 等积性、Helmert 双约定）

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
与 PROJ 的 `PJ` 结构体加运算链表架构没有对应关系；第三方依赖为 0，外部数据文件为 0。

## 仓库与提交记录

仓库地址：https://github.com/wuhaiting321/mooncrs

提交按功能模块组织，每个提交是一个完整的独立增量，不含格式化噪音、空提交或重复提交：

| # | 提交内容 |
| ---: | --- |
| 1 | 初始化 MoonBit 模块、包骨架、许可证与忽略规则 |
| 2 | `types`：椭球、单位、基准、Helmert 与 CRS 数据模型 |
| 3 | `projection`：公共数学（子午线弧长、等角纬度、authalic q）与 Krüger 级数 |
| 4 | `projection`：墨卡托、LCC、Albers、极射赤面、LAEA、Cassini |
| 5 | `projection`：Hotine 斜轴墨卡托 variant B |
| 6 | `projection`：投影结构与 12 种方法的分派 |
| 7 | `wkt`：词法与递归下降解析（WKT1 / WKT2） |
| 8 | `wkt`：语义层（→ Crs）与 WKT2 生成 |
| 9 | `projstr`：PROJ 串解析、`+zone`/`+south` 展开与生成 |
| 10 | `epsg`：内置注册表（含 UTM 与 CGCS2000 公式族生成） |
| 11 | `crs`：大地↔地心几何、Helmert 正反、六步转换管道 |
| 12 | `crs`：四种输入格式判别与人类可读描述 |
| 13 | `cmd/main`：CLI 六条子命令 |
| 14 | `test`：EPSG 官方案例与闭环回归套件（62 个测试） |
| 15 | `docs`：项目申报书与验收文档 |

复现验证：

```bash
moon check      # 0 error, 0 warning
moon test       # Total tests: 62, passed: 62, failed: 0
find . -name "*.mbt" -not -path "./_build/*" | xargs wc -l | tail -1   # 7148
```

## 许可证

Apache License 2.0（见 [LICENSE](LICENSE)）。
