# Axon SDK 概览

Axon 提供从生理信号设备接入、实时处理到录制、导出和发布的完整链路。采集与算法在 Rust 内核中实现，Rust 应用使用 `axon-api`，C、Dart/Flutter、Python 和 C#/.NET 应用通过公共 C ABI 接入。

本文介绍 SDK 能力；具体语言可用入口见[接口参考](api.md)，运行环境准备见[接入指南](getting-started.md)。

## 设备与数据流

- **Lychee 设备接入**：按设备能力提供 EEG、NIRS 和运动等数据流，支持 TCP、UDP 单播/组播、BLE、USB 和串口。网络设备可自动发现；BLE 使用扫描、选择、显式连接的流程。
- **多设备、多流**：设备通过稳定的 serial 标识；每条流独立描述采样模式、采样率、通道、单位与 metadata。不要假定所有设备都有 `eeg` 或相同的通道数。
- **无硬件开发**：内置 Lychee 模拟器、可配置 EEG/NIRS 的 Custom 模拟器，以及 EDF/AXF 文件回放。它们通过普通设备查询和 Session 消费数据。
- **厂商扩展**：Rust 可通过 `DeviceProvider` SPI 接入自定义设备。发现、连接与厂商控制属于具体 provider，应用的订阅和录制流程保持一致。

通用数据模型可承载 EEG、fNIRS、EMG、ECG、EOG、PPG、IMU 等信号；具体硬件可采集的模态和连接方式取决于设备与 provider。

## 信号处理与分析

SDK 提供低通、高通、带通、带阻和陷波等滤波能力，并提供频谱、频段功率、注意力相关指标与时间域质量分析。可以同时保留原始数据并建立独立处理管线，分别用于显示、分析和录制。

Rust 算法层还提供去趋势、重采样、Welch PSD、小波时频分析、相干性、CCA 和 SSA 等能力。这些能力不一定都由各语言的实时订阅接口暴露，应按具体语言契约选择入口。

均匀采样流可进入处理管线；不规则采样流可原样读取和录制，必须保留逐帧时间信息，不能使用名义采样率推算实际帧时间。

## 录制与文件互操作

| 能力 | 用途 |
| --- | --- |
| AXF 流式录制 | 增量保存采集数据，支持多流格式、压缩、可选量化和随机访问 |
| 事件与 metadata | 保存实验注释、参与者与录制信息、通道及模态描述 |
| AXF 读取 | 查询流、metadata、事件，按块或时间范围读取样本 |
| 格式导出 | 指定 AXF 流导出 EDF/BDF/CSV，或将整份录制导出为 XDF |
| 数据集组织 | 按 GB/T 47127 相关信息组织并导出数据集目录 |
| 独立 AXF writer | 不连接设备，将已有样本和事件写入 AXF |

AXF 文件缺少正常关闭时的 Footer，可扫描完整有效的 chunk 前缀恢复。录制仍须显式 `finish` 才保存；关闭数据源会取消未完成录制。多流文件应显式选择导出流，不要把它当作单一信号矩阵。

## LSL 实时发布

实时原始订阅和处理管线输出可以发布为 Lab Streaming Layer（LSL）outlet，供 LabRecorder 等工具接收。发布与 AXF 录制独立，需保留 publisher 句柄，并部署匹配平台的 liblsl。

当前 LSL 支持范围是 Windows、Linux、macOS 桌面实时流发布；历史回放发布、LSL 接收、事件标记 outlet 和移动端打包不在此范围内。

## 语言与平台

| 接口 | 入口与适用场景 |
| --- | --- |
| Rust | `axon-api` 高层采集 API；自定义厂商使用 `axon-provider-api` SPI |
| C | `axon.h` 定义句柄、结构体、回调和所有权契约 |
| Python | `axon` 包，适合算法验证、采集脚本和桌面应用 |
| Dart/Flutter | `axon_dart` 包，以异步 Stream 消费数据 |
| C#/.NET | `Axon` 包，以 reader 消费数据，适合 .NET 桌面应用 |

本仓库的示例面向桌面：Python 与 Flutter 提供桌面监测，.NET 示例使用 Windows WPF。原生库和语言包需匹配操作系统与 CPU 架构；不能因 Flutter 支持移动端就直接复用桌面原生 bundle。Swift、Kotlin/Java 专用 SDK 与移动端打包属于后续规划。

## Axon Studio 与典型场景

Axon Studio 是基于 SDK 的桌面调试工具，提供波形、频谱、注意力、NIRS、事件标记、录制和 LSL 发布，并包含信号诊断、模拟器、文件回放、设备配网、固件升级和格式转换等工具。设备配网和固件升级通过厂商控制接口提供。

| 场景 | 推荐起点 |
| --- | --- |
| 无硬件开发应用 | Custom 模拟器 → 查询流 → 原始订阅或处理管线 |
| 科研采集与实验记录 | 真实设备 → 原始订阅 → AXF 录制、metadata 与事件 |
| 在线信号分析 | 均匀采样流 → 处理管线 → 处理后订阅与分析 |
| 接入科研工具链 | 实时 LSL 发布，或录制后离线导出 XDF/EDF |
| 算法复现与离线处理 | EDF/AXF 回放、AXF reader 与独立 writer |

继续阅读：[接入指南](getting-started.md)、[接口参考](api.md)。返回[仓库首页](../README.md)。
