# flutter_demo

Flutter 桌面 demo：实时波形、频谱和信号分析，消费本地 `axon_dart` ABI 0.2 绑定。

本示例显式选择均匀采样 EEG 流，从流查询读取采样率和通道数。
Motion 或其他非均匀采样流不适用于此示例的滤波和波形时间轴。
停止采集只释放 session 和模拟器，设备发现持续到窗口关闭。

## 运行

1. 构建原生库：

   ```sh
   cd ../../axon
   cargo build -p axon-ffi --release
   cd ../axon-examples/flutter
   ```

2. 刷新本地绑定依赖，并指定匹配的 ABI 0.2 原生库：

   ```sh
   flutter pub get
   flutter run -d macos --dart-define=AXON_LIB_PATH=$PWD/../../axon/target/release/libaxon.dylib
   ```

   Windows PowerShell：

   ```powershell
   flutter run -d windows --dart-define=AXON_LIB_PATH=D:/code/Rust/axon/target/release/axon.dll
   ```

## 测试

```sh
flutter test
```
