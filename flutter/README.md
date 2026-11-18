# Flutter EEG 示例

桌面波形、频谱和信号分析，使用 0.10.0 绑定和匹配的原生 ABI 0.10.x。
Flutter SDK 有两种交付方式：访问自建 Pub 仓库，或使用 SDK 压缩包。
本仓库默认的相邻源码依赖用于 SDK 联调，见后文的源码开发说明。

默认创建 Lychee BCI100 厂商模拟器（3 通道、250 Hz）；也可选择已发现的 Lychee 设备。
流、采样率、通道数和标签从设备描述读取。此示例选择均匀采样 EEG，
Motion 等不规则流不适用于这里的滤波和波形时间轴。
频谱消息每条只包含一个通道，画布按 `channelIndex` 选择显示通道。
停止只释放订阅、pipeline、设备 Session 和模拟器，设备发现持续到窗口关闭。

## 注意力分数视图（本轮预览）

选择“注意力分数”可查看当前分数与趋势曲线：纵轴固定为 0–100，横轴为
相对时间，保留最近 200 个结果。鼠标移到曲线上可查看对应分数与时间。
每个完整的 2 秒窗口更新一次；开始时显示等待状态，伪迹保持点以橙色标记。
伪迹窗口尚未产生有效分数时不会把初始零值显示为有效读数。

注意力由 SDK 的 `AttentionScore` 计算，汇总全部 EEG 通道，使用独立的
未滤波处理分支；通道选择和波形滤波设置不影响它。切换视图继续收集历史，
停止后保留本轮曲线；再次开始或更换数据源时清空。断开、恢复或计算错误会
清除失效的读数并显示状态。该分数与“信号”页已有的 Focus/Calm/SQI 指标不同。

本功能需要包含新增注意力接口的 Dart 绑定和原生库，之前发布的 0.10.0 SDK
ZIP / Pub 包尚不包含这些接口。本轮请使用相邻源码开发方式，重新执行
`pwsh ../../axon/scripts/build-native.ps1 -Profile debug`，并确保没有旧 SDK 的
`pubspec_overrides.yaml` 覆盖源码绑定；`AXON_LIB_PATH` 指向此次构建的动态库。
旧原生库缺少接口时，注意力页显示错误，其余视图仍可使用。

本轮只提供 Flutter 预览，Python 和 C# 示例将在效果确认后同步。
预览正常分数曲线可选择“EEG 分数模拟器”（SDK 自定义模拟器，3 通道、250 Hz）。
原有 BCI100 协议模拟器保留；其当前信号会触发评分的幅值伪迹判定，可能持续
显示伪迹保持状态。评分规则和真实设备输入均未作缩放或替换。

## 选择接入方式

| 方式 | Dart 绑定来源 | 原生库来源 |
| --- | --- | --- |
| 自建 Pub 仓库 | 从 Gitea 的 LycheePublic 拉取 `axon_dart` | 单独准备同版本、同平台/架构的原生包，也可使用 SDK ZIP 内的 `native/<rid>/` |
| SDK 压缩包 | 解压后通过 `path` 引用 `axon_dart/` | 同一 ZIP 内的 `native/<rid>/` |

两种方式均无需检出 Axon 源码或安装 Rust。当前 Pub 包只包含 Dart 绑定，不会自动安装或部署原生库。下面两种依赖配置选择一种，不要同时创建。

## 方式一：访问自建 Pub 仓库

当前自建（私有部署）Pub 仓库地址：

```text
http://192.168.1.250:30000/api/packages/LycheePublic/pub/
```

这里“私有”指自建包仓库；`LycheePublic` 中的包允许匿名读取，不需要 Token。若其他仓库要求认证，需要使用 HTTPS 并通过 `dart pub token add <仓库地址>` 配置凭据；Dart 不支持向此类内网 HTTP 地址配置认证。不要把 Token 写入 YAML 或 URL。

独立 Flutter 项目的 `pubspec.yaml` 可以声明：

```yaml
dependencies:
  axon_dart:
    hosted: http://192.168.1.250:30000/api/packages/LycheePublic/pub/
    version: 0.10.0
```

在本示例仓库中，创建 `flutter/pubspec_overrides.yaml` 覆盖默认源码依赖：

```yaml
dependency_overrides:
  axon_dart:
    hosted: http://192.168.1.250:30000/api/packages/LycheePublic/pub/
    version: 0.10.0
```

然后在 `flutter/` 执行 `flutter pub get`。如果已有 SDK ZIP，将其中的原生库保留在 `vendor/axon-sdk/native/`，Windows x64 运行方式为：

```powershell
flutter pub get
$env:AXON_LIB_PATH = (Resolve-Path ../vendor/axon-sdk/native/win-x64/axon.dll).Path
flutter run -d windows
```

**当前网络限制：** 已发布 `axon_dart 0.10.0`，入口的匿名元数据和直接包文件下载均已验证。但 Gitea 返回的 `archive_url` 使用 `192.168.35.251:30000`，在本次验证环境中不可达，因此完整的 Flutter 拉取尚未通过。客户端需能访问该下载地址，或使用发布方提供的、会改写下载地址的 Pub 代理入口；仅更改 `hosted` 地址不能改变服务器返回的下载地址。网络未解决时可使用下面的压缩包方式。

## 方式二：使用 SDK 压缩包

从 SDK 提供方获取与系统、CPU 架构匹配的 `axon-flutter-sdk-<version>-<rid>-release.zip`。包同时包含 Dart 绑定、原生库、LSL 许可证和 `sdk.json`；保持整包版本一致。只需 Flutter/Dart 环境，无需 Rust 工具链。

在 axon-examples 根目录解压，将 ZIP 中的顶层目录重命名为 `axon-sdk` 并放入 `vendor/`：

```text
axon-examples/
├─ vendor/axon-sdk/
│  ├─ axon_dart/pubspec.yaml
│  ├─ axon_dart/lib/
│  ├─ native/win-x64/axon.dll
│  ├─ native/win-x64/lsl.dll
│  └─ native/win-x64/LSL-*.txt
└─ flutter/
   ├─ pubspec.yaml
   └─ pubspec_overrides.yaml
```

创建 `flutter/pubspec_overrides.yaml`，覆盖本仓库默认的相邻源码依赖：

```yaml
dependency_overrides:
  axon_dart:
    path: ../vendor/axon-sdk/axon_dart
```

在 `flutter/` 目录执行（Windows x64）：

```powershell
flutter pub get
$env:AXON_LIB_PATH = (Resolve-Path ../vendor/axon-sdk/native/win-x64/axon.dll).Path
flutter run -d windows
```

`vendor/` 和覆盖文件已被 Git 忽略，不提交本机 SDK。`pub get` 会更新锁文件中的本地路径；仅为本机切换包来源时不要提交该路径变化。恢复源码模式时移除覆盖文件，再执行 `flutter pub get`。包版本应与本仓库支持的 ABI 一致，不能只替换 Dart 文件或 DLL。

Linux 对应 `native/linux-x64/libaxon.so`（ARM64 替换 RID）；macOS 对应 `native/osx-arm64/libaxon.dylib` 或 `osx-x64`，沙盒应用仍需下文的嵌入与签名。

## 两种方式共用的应用部署

Flutter 不会自动将此 SDK 的原生库复制到应用。Windows 执行 `flutter build windows --release` 后，将 `native/win-x64/` 的运行库和许可证一起复制到 `build/windows/x64/runner/Release/`，分发整个应用目录。

当前示例的 `Axon()` 使用 `AXON_LIB_PATH` 加载；打包独立应用时，可改成相对可执行文件加载，避免依赖开发机绝对路径：

```dart
import 'dart:ffi';
import 'dart:io';
import 'package:axon_dart/axon.dart';

final directory = File(Platform.resolvedExecutable).parent.path;
final axon = Axon(
  library: DynamicLibrary.open(
    '$directory${Platform.pathSeparator}axon.dll',
  ),
);
```

Linux 使用 `libaxon.so`，同样保留 liblsl 及其版本别名；macOS 采用下文的 Frameworks 布局。原生库不放入 Flutter assets，也不要将开发机的 `AXON_LIB_PATH` 通过 `--dart-define` 固化进分发应用。

## 相邻源码开发（Windows）

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
