# hc155-89/mooncrs

坐标参考系（CRS）转换引擎。核心包零外部依赖；网格数据按需自备，不随库分发。

```
moon add hc155-89/mooncrs
```

配套 CLI（`moon run cmd/main -- ...`）：

```
mooncrs transform <源CRS> <目标CRS> <x> <y>     # 转换
mooncrs ops --from <源> --to <目标> --point <x> <y>
                                                # 先看有哪些候选运算、是否适用
mooncrs describe  <CRS>
mooncrs wkt       <CRS>
mooncrs proj      <CRS>
```

支持 WKT2:2019 / WKT1 / PROJ 串 / EPSG 码四种输入，12 种投影方法，
坐标运算注册表（同一对基准可有多条运算，各带适用范围与标称精度），
NTv2（`.gsb`）网格改正，内置 250 个 EPSG 坐标系。

**不承诺"任意跨基准精确转换"**：精度取决于用哪条运算、需要什么数据、你的点
是否在适用范围内。`--explain` 与 `ops` 就是为了说明这三件事而存在。

- 精度判据与不支持清单：[docs/ACCURACY.md](docs/ACCURACY.md)
- 网格数据来源与许可：[docs/DATA.md](docs/DATA.md)
- 逐点验证数字：[docs/VERIFICATION.md](docs/VERIFICATION.md)
- 完整文档：[README.md](README.md)
