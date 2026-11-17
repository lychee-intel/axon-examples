# Flutter EEG 示例

桌面波形、频谱和信号分析，使用相邻 `axon/bindings/dart` 中的 0.10.0
绑定和匹配的原生 ABI 0.10.x。

默认创建 Lychee BCI100 厂商模拟器（3 通道、250 Hz）；也可选择已发现的 Lychee 设备。
流、采样率、通道数和标签从设备描述读取。此示例选择均匀采样 EEG，
Motion 等不规则流不适用于这里的滤波和波形时间轴。
频谱消息每条只包含一个通道，画布按 `channelIndex` 选择显示通道。
停止只释放订阅、pipeline、设备 Session 和模拟器，设备发现持续到窗口关闭。

## Windows 运行

在本目录执行，需安装 Flutter、Rust、Python 和 PowerShell（`pwsh`）：

```powershell
pwsh ../../axon/scripts/build-native.ps1 -Profile debug
flutter pub get
$env:AXON_LIB_PATH = (Resolve-Path ../../axon/outputs/native/windows/debug/axon.dll).Path
flutter run -d windows
```

Release 使用 `-Profile release` 和对应的 `outputs/native/windows/release/axon.dll`。
部署时保留原生包中的 `axon.dll`、`lsl.dll` 和 `LSL-*.txt`，并让
`AXON_LIB_PATH` 指向完整路径；也可使用 `--dart-define=AXON_LIB_PATH=...`。

## macOS

用同一脚本构建 macOS 原生包，产物在 `outputs/native/macos/<profile>/`。
将 `libaxon.dylib`、`liblsl.dylib` 和许可证嵌入应用的 `Contents/Frameworks`，
在 Xcode 中为动态库启用 Copy Files / Code Sign On Copy；绑定会从该位置加载。
沙盒应用需要签名并嵌入运行库，指向相邻仓库的路径不能替代此步骤。
原生构建和应用架构须一致。

## 检查

```sh
flutter analyze
flutter test
flutter build windows --debug
```

独立文件、录制、健康状态、离线 EEG PSD 和频带峰值的 SDK 示例见
[Dart 接口参考](../docs/api/dart.md)。
