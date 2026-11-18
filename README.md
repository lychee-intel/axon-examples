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

## Zed 运行入口（Windows）

用 Zed 打开 `axon-examples` 根目录，执行命令面板中的 `task: spawn`，选择
`Run: Python Lychee Monitor`、`Run: Flutter EEG (Windows)` 或
`Run: .NET Lychee Monitor (Windows)`。三个入口定义在 `.zed/tasks.json`，
通过终端运行，不启动 Zed 调试器；`task: rerun` 可再次运行最近的任务。
Flutter 沿用 `flutter run` 默认的 debug 构建模式，保留热重载。

启动项使用已安装的 **0.10.0 SDK**，无需检出或构建相邻 `axon` 源码仓库。

- Python：按 Python README 将发布的 wheel 安装到 `python/.venv`，任务通过
  `uv run` 使用该环境和 wheel 自带的原生库。不要安装源码 editable 包；
  任务清空 `AXON_LIB_PATH`，避免继承其他环境中的源码构建路径。
- Flutter：按 Flutter README 的 SDK 压缩包方式安装到 `vendor/axon-sdk/`，
  创建 `flutter/pubspec_overrides.yaml` 指向包内的 `axon_dart`，再执行
  `flutter pub get`。也可使用 Pub 绑定和同版 SDK 原生库。
  任务通过 `--no-pub` 直接使用已准备的依赖，避免运行时重新解析默认源码依赖，
  并将 `AXON_LIB_PATH` 指向 `vendor/axon-sdk/native/win-x64/axon.dll`。
  SDK 安装在其他目录时，修改任务中的这个路径。
- .NET：将发布的 `Axon.0.10.0.nupkg` 放入 `dotnet/packages/`，任务传入
  `-p:AxonProjectPath=` 强制使用 NuGet 包，即使存在相邻源码也不会引用它。

三个示例默认使用相同的设备监听端口，验证模拟器时请逐个运行，关闭前一个窗口后
再启动下一个，避免端口占用。

## 版本兼容

Python、Flutter 与 .NET 示例统一使用 **0.10.0 语言绑定及 ABI 0.10.x**。相邻源码模式引用当前绑定，独立 .NET 模式使用匹配的 0.10.0 NuGet 包。Python 的安装与源码开发方式见其子目录。

Flutter SDK 支持两种交付方式：访问自建 Pub 仓库，或使用 SDK 压缩包。Pub 当前只提供 Dart 绑定，原生库需另行准备；压缩包同时包含绑定与对应运行库。配置方法和当前 Pub 网络限制见 [Flutter README](flutter/README.md)。

升级时需同步更新语言绑定及原生动态库；绑定会拒绝不匹配的 ABI 主、次版本。使用与你的操作系统和 CPU 架构匹配的 SDK 发布包，安装与部署步骤见[接入指南](docs/getting-started.md)。
