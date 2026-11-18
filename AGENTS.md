# AGENTS.md

本仓库包含 Axon 的 Python、Flutter 和 .NET 示例及 SDK 使用文档。按示例所属语言验证，保持语言绑定与原生 ABI 匹配；当前基线为 0.10.0。不要在示例仓库复制或重新实现底层 C ABI。

## Flutter SDK 接入：Pub 或压缩包

- 完整步骤以 [flutter/README.md](flutter/README.md) 为准。Flutter 有两种交付接入方式：自建 Pub 仓库，或 SDK 压缩包；均无需使用方检出 Axon 或安装 Rust。默认相邻源码依赖保留用于联调。
- Pub：在 `flutter/pubspec_overrides.yaml` 中为 `axon_dart` 配置 hosted 地址 `http://192.168.1.250:30000/api/packages/LycheePublic/pub/` 和 `version: 0.10.3`，然后执行 `flutter pub get`。该组织允许匿名读。0.10.3 一体化包内置 Windows x64 Release Axon/LSL DLL 和许可证，Flutter 构建自动部署，`Axon()` 自动加载，无需单独复制库或设置 AXON_LIB_PATH。
- 一体化包目前仅支持 Windows x64；其他桌面平台使用匹配 ABI 的 SDK ZIP。当前 Gitea 下载地址为 `192.168.1.250:30000`；`latest` 可能返回旧版，需显式指定版本。要求认证的仓库需 HTTPS，不在仓库文件中存 Token。
- 压缩包：将 SDK 解压到仓库的 `vendor/axon-sdk/`，通过 `flutter/pubspec_overrides.yaml` 的 `dependency_overrides.axon_dart.path: ../vendor/axon-sdk/axon_dart` 覆盖默认源码依赖，再执行 `flutter pub get`。绑定与 `native/<rid>/` 使用同一版 SDK。Pub 和 path 覆盖配置二选一。
- 本机 vendor、pubspec_overrides.yaml 和机器绝对路径不提交；默认 pubspec 保留相邻源码开发方式。切换依赖路径时不要把本机 SDK 路径产生的 lockfile 改动带入无关提交。
- SDK ZIP / 源码模式运行前将 `AXON_LIB_PATH` 指向当前平台/架构的 Axon 动态库；Pub 一体化 Windows 模式无需此配置。发布应用必须同时带上 LSL 运行库及许可证；一体化插件自动部署，ZIP 手工复制。macOS 嵌入并签名 `Contents/Frameworks` 中的库。Flutter assets 不替代原生运行库部署。
- 更改接入方式后验证 `flutter analyze`、`flutter test`，并运行 SDK 原生模拟器收样；可用时再构建相应桌面应用。两个仓库的打包布局变化时，同步更新此文件和 Flutter README。Axon 生产包入口为相邻仓库的 `scripts/build-flutter-sdk.ps1`，细节见其 `docs/guides/flutter-sdk.md`。

## 检查

- Python：在安装匹配绑定的环境中执行 `python -m unittest discover -s python/tests -v`；设置 `AXON_RUN_NATIVE_TESTS=1` 后包含原生集成测试。
- .NET：执行 `dotnet build dotnet/src/LycheeMonitor.csproj` 与 `dotnet test dotnet/tests/WaveformBufferTests.csproj`。
- 交付前对本次改动执行 `git diff --check`，报告实际运行的检查与未覆盖的平台。
