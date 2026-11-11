// mooncrs —— 纯 MoonBit 实现的坐标参考系（CRS）转换引擎。

///|
/// 库版本号，与 moon.mod 保持一致。
pub let version : String = "0.1.0"

///|
/// 一句话介绍，供 CLI 的 `--version` 输出使用。
pub fn about() -> String {
  "mooncrs " + version + " — 坐标参考系转换引擎（WKT2 / EPSG / PROJ 串）"
}
