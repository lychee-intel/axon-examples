# Axon Examples

Axon 是力之的生理信号采集SDK，用于采集、分析、存储脑电、肌电、脑氧等生理信号。
本仓库包含 Axon 的跨语言示例程序，每个子目录对应一种语言。

目前支持以下语言：

- [Python](python/README.md)
- [.NET (C#)](dotnet/README.md)
- [Flutter (Dart)](flutter/README.md)

## ABI 0.2

三个示例使用 Axon ABI 0.2 的 binding 和原生库。升级时需要同时更新 Python
wheel、C# NuGet 包或 Flutter 的本地 Dart 依赖，以及对应的原生动态库；只替换
其中一层会被 binding 的 ABI 版本检查拒绝。

采集示例选择设备的均匀采样 EEG 流。采样率和通道数通过流查询接口
获取，设备信息仅用于身份和能力查询。滤波器直接使用所选流的采样率，无需在
滤波配置中重复传入。新增的 AXF 导出、metadata、质量分析和 Motion 接口仍可从
binding 使用，此次更新不为它们新增演示界面。

各语言的依赖更新、构建和测试步骤见上面的子目录说明。
