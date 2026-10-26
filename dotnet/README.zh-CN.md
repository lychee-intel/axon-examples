# Axon .NET 示例 — Lychee EEG 监测器

基于 WPF 的桌面应用，使用 Axon C# 绑定和 ScottPlot 实时显示 Lychee 设备或内置 Lychee PFC 模拟器的 EEG 波形。

## 功能

- **设备发现** — 自动检测局域网上的 Lychee EEG 硬件
- **模拟器** — Axon 启动后点击页面上的 **Add simulator**，创建虚拟 3 通道、250 Hz 设备
- **自定义模拟器** — 点击 **Add custom simulator** 设置 serial、0–64 个 EEG 通道，并可选启用双通道 NIRS
- **实时波形** — 滚动多通道 EEG 显示，自动量程
- **0.4–70 Hz 带通滤波** — 默认启用 IIR 单节滤波器，与原生调试器一致（`--no-filter` 可禁用，`--notch` 叠加 50 Hz 陷波）
- **暗色主题** — 与 Python 示例一致的视觉风格

## ABI 0.2 升级

本示例使用匹配的 Axon 0.2.0 binding 和原生 DLL，并显式选择均匀采样 EEG 流。
在本目录执行以下命令重新打包、恢复依赖：

当 `axon` 与 `axon-examples` 仓库位于同一父目录时，项目会默认引用 `axon/bindings/dotnet/Axon` 源码；独立检出时使用下方打包的 NuGet 包。

本地源码模式运行前，先在 `axon` 仓库根目录构建对应配置的原生库；示例构建时会将其复制到应用输出目录，避免误加载系统中其他版本的 `axon.dll`。

```powershell
cargo build -p axon-ffi
```

```powershell
$axon = (Resolve-Path ..\..\axon).Path
cargo build --manifest-path "$axon\Cargo.toml" -p axon-ffi --release
$stage = Join-Path $PWD '..\target\axon-package-abi020'
$native = Join-Path $stage 'win-x64\native'
New-Item -ItemType Directory -Force $native | Out-Null
Copy-Item "$axon\target\release\axon.dll" (Join-Path $native 'axon.dll') -Force
dotnet pack (Join-Path $axon 'bindings\dotnet\Axon\Axon.csproj') -c Release "-p:AxonNativeLibDir=$stage" -o .\packages
dotnet restore src --force --no-http-cache
dotnet restore tests --force --no-http-cache
```

同版本替换包时，先移除 `../target/dotnet-nuget-cache-abi020/axon/0.2.0` 缓存目录，再执行恢复。

## 环境要求

- .NET 8.0+ SDK

`Axon` NuGet 包（含原生 `axon.dll`）已包含在 `dotnet/packages/` 中。
如需从 `axon` 仓库重新打包：

```bash
# 在 axon 仓库根目录
.\scripts\build-dotnet-nuget.ps1
# 然后将 .nupkg 复制到此处
cp outputs/Axon.*.nupkg ../axon-examples/dotnet/packages/
```

## 运行

```bash
# 启动应用后，在页面上点击 Add simulator（无需硬件）
dotnet run --project src

# 指定设备 serial
dotnet run --project src -- --serial AABBCC

# 自定义时窗、禁用滤波
dotnet run --project src -- --window 10 --no-filter

# 显示帮助
dotnet run --project src -- --help
```

## 命令行参数

| 参数 | 说明 |
|---|---|
| `--serial HEX` | 按 6 位十六进制 serial 添加设备 |
| `--window SECONDS` | 波形显示时窗（默认 10.0 秒） |
| `--no-filter` | 禁用 0.4–70 Hz 带通滤波器 |
| `--notch` | 叠加 50 Hz 陷波（Q=30），接硬件时使用 |
| `--log-level LEVEL` | 最低日志严重等级：trace, debug, information, warning, error, critical, none（默认） |

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
│   └── Axon.0.2.0.nupkg          # Axon 绑定 NuGet 包（含原生库）
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
