# hc155-89/mooncrs

坐标参考系（CRS）转换引擎。零外部依赖，零网格文件。

```
moon add hc155-89/mooncrs
```

配套 CLI（`moon run cmd/main -- ...`）：

```
mooncrs transform <源CRS> <目标CRS> <x> <y>
mooncrs describe  <CRS>
mooncrs wkt       <CRS>
mooncrs proj      <CRS>
```

支持 WKT2:2019 / WKT1 / PROJ 串 / EPSG 码四种输入，12 种投影方法，
Helmert 七参数基准变换，内置 250 个 EPSG 坐标系。

完整文档见 [README.md](README.md)。
