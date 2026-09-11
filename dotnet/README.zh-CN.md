# Axon .NET 示例 — Lychee EEG 监测器

基于 WPF 的桌面应用，使用 Axon C# 绑定和 ScottPlot 实时显示 Lychee 设备或内置模拟器的 EEG 波形。

## 功能

- **设备发现** — 自动检测局域网上的 Lychee EEG 硬件
- **模拟器模式** — `--sim` 创建虚拟3通道、250 Hz 设备
- **实时波形** — 滚动多通道 EEG 显示，自动量程
- **0.4–70 Hz 带通滤波** — 默认启用 IIR 单节滤波器，与原生调试器一致（`--no-filter` 可禁用，`--notch` 叠加 50 Hz 陷波）
- **暗色主题** — 与 Python 示例一致的视觉风格

## 环境要求

- .NET 8.0+ SDK

`Axon` NuGet 包（含原生 `axon.dll`）已包含在 `dotnet/packages/` 中。
如需从 `axon` 仓库重新打包：

```bash
# 在 axon 仓库根目录
.\scripts\build-dotnet-nuget.ps1
# 然后将 .nupkg 复制到此处
cp bindings/dotnet/Axon/bin/Release/Axon.*.nupkg ../axon-examples/dotnet/packages/
```

## 运行

```bash
# 模拟器模式（无需硬件）
dotnet run --project src -- --sim

# 指定设备 serial
dotnet run --project src -- --serial AABBCC

# 自定义时窗、禁用滤波
dotnet run --project src -- --sim --window 10 --no-filter

# 显示帮助
dotnet run --project src -- --help
```

## 命令行参数

| 参数 | 说明 |
|---|---|
| `--sim` | 使用内置模拟器（无需硬件） |
| `--serial HEX` | 按 6 位十六进制 serial 添加设备 |
| `--window SECONDS` | 波形显示时窗（默认 10.0 秒） |
| `--no-filter` | 禁用 0.4–70 Hz 带通滤波器 |
| `--notch` | 叠加 50 Hz 陷波（Q=30），接硬件时使用 |
| `--log-level LEVEL` | Rust 日志级别：off, error, warn, info, debug, trace |

## 构建

```bash
dotnet build src
dotnet test tests
```

## 项目结构

```
dotnet/
├── LycheeMonitor.sln
├── nuget.config                   # 本地 NuGet 源，指向 packages/
├── packages/
│   └── Axon.0.1.0.nupkg          # Axon 绑定 NuGet 包（含原生库）
├── src/
│   ├── LycheeMonitor.csproj       # WPF 应用 (net8.0-windows)
│   ├── Program.cs                 # 入口 + 命令行解析
│   ├── MainWindow.xaml            # WPF 布局 (XAML)
│   ├── MainWindow.xaml.cs         # 应用逻辑 + ScottPlot 渲染
│   └── WaveformBuffer.cs          # 线程安全的环形采样缓冲区
└── tests/
    ├── WaveformBufferTests.csproj
    └── WaveformBufferTests.cs     # WaveformBuffer 单元测试
```
