# Axon Examples

Axon 是力之的生理信号采集与处理 SDK，以 Rust 实现采集、信号处理和文件读写，通过 C ABI 为 Dart/Flutter、Python 和 C#/.NET 提供绑定。应用可以从设备发现开始，完成多流订阅、实时分析、AXF 录制、格式导出和 LSL 实时发布。

本仓库包含 SDK 使用说明、接口参考与跨语言示例程序。无需硬件时，可以使用内置模拟器或 EDF/AXF 文件回放开发应用。

## SDK 文档

| 文档 | 内容 |
| --- | --- |
| [SDK 概览](docs/overview.md) | 核心能力、设备与数据流、语言与平台、典型使用场景 |
| [接入指南](docs/getting-started.md) | 运行库准备、采集流程、无硬件 Python 示例与资源释放 |
| [接口参考](docs/api.md) | 跨语言速查，以及 Python、Dart/Flutter、.NET 详细手册与数据类型约定 |

建议先阅读概览和接入指南，再按接口参考中的语言对照表查找具体入口。

## 示例程序

| 语言 | 示例 | 运行说明 |
| --- | --- | --- |
| Python | Lychee EEG 实时波形监测 | [Python README](python/README.md) |
| C#/.NET | WPF EEG 监测器 | [.NET 中文说明](dotnet/README.zh-CN.md)、[English](dotnet/README.md) |
| Dart/Flutter | 桌面波形、频谱和信号分析 | [Flutter README](flutter/README.md) |

这些监测示例选择均匀采样 EEG 流，从流描述读取采样率和通道数。SDK 还支持其他原始数据流、文件操作和发布能力，具体入口见接口参考。

## 版本兼容

Flutter 与 .NET 示例使用 **0.10.0 语言绑定及 ABI 0.10.x**。相邻源码模式引用当前绑定，独立 .NET 模式使用匹配的 0.10.0 NuGet 包。Python 示例的依赖与运行说明见其子目录。

升级时需同步更新语言绑定及原生动态库；绑定会拒绝不匹配的 ABI 主、次版本。使用与你的操作系统和 CPU 架构匹配的 SDK 发布包，安装与部署步骤见[接入指南](docs/getting-started.md)。
