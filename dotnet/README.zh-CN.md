# Axon .NET 示例 — Lychee EEG 监测器

[English](README.md)

基于 WPF、Axon 0.10.0 绑定（原生 ABI 0.10.x）和 ScottPlot 的 EEG 波形监测器。
从设备描述中选择均匀采样 EEG 流，读取实际采样率与通道数。

- **Add Lychee BCI100** 创建厂商模拟器：3 通道 EEG、250 Hz。
- 默认启用 0.4–70 Hz IIR 带通；`--no-filter` 禁用，`--notch` 叠加 50 Hz 陷波。
- 停止采集释放订阅、pipeline 和设备 Session，窗口关闭时结束设备发现。

## 构建与运行

需要 Windows、.NET 8 或更新 SDK、Rust、Python 和 PowerShell（`pwsh`）。
将 `axon` 与 `axon-examples` 放在同一父目录；在本目录执行：

```powershell
pwsh ../../axon/scripts/build-native.ps1 -Profile debug
dotnet run --project src
dotnet test tests
```

运行 `dotnet run --project src -c Release` 前，使用 `-Profile release` 构建原生包。
源码引用模式会从 `axon/outputs/native/windows/<configuration>/` 复制
`axon.dll`、`lsl.dll` 和 `LSL-*.txt` 到程序旁边。缺少原生包时构建会给出准备命令。
可用 `AxonNativeDllPath` 指向另一份完整、匹配的原生包。

采集采用设备 Session → EEG stream → processing pipeline → output subscription；
数据经托管 reader 传递，WPF 在 Dispatcher 上更新界面。

## 独立 NuGet 模式

找不到相邻绑定源码时，应用及测试使用 `packages/` 中的 Axon 0.10.0。
从 Axon 源码生成包含匹配运行库的 NuGet 包：

```powershell
$axon = (Resolve-Path ../../axon).Path
pwsh "$axon/scripts/build-native.ps1" -Profile release
dotnet pack "$axon/bindings/dotnet/Axon/Axon.csproj" -c Release `
  "-p:AxonNativeLibDir=$axon/outputs/native/windows/release" `
  -p:AxonNativeRuntimeIdentifier=win-x64 -o ./packages
dotnet restore src --force
dotnet restore tests --force
```

ARM64 原生包使用 `win-arm64`。Axon、LSL 库和许可证须一起部署。
本地缓存位于 `../target/dotnet-nuget-cache`；同版本替换包时只清理其中
`axon/0.10.0`，再恢复依赖。

## 命令行参数

| 参数 | 说明 |
| --- | --- |
| `--serial HEX` | 指定六位十六进制 serial |
| `--window SECONDS` | 波形窗口，默认 10 秒 |
| `--no-filter` | 禁用 0.4–70 Hz 带通 |
| `--notch` | 叠加 50 Hz 陷波，Q=30 |
| `--log-level LEVEL` | trace、debug、information、warning、error、critical、none（默认） |
| `--help` | 显示帮助 |

例如：`dotnet run --project src -- --serial AABBCC --window 10 --notch`。

当前绑定还提供独立 AXF 文件操作、离线 EEG 窗口/PSD 分析、原生频带峰值、
传输健康状态和 LSL 发布。用法见 [.NET 接口参考](../docs/api/dotnet.md)。
