# flutter_demo

Flutter macOS 桌面 demo：实时波形 + EDF 存读，消费 `axon_dart`（Axon EEG 的 Dart 绑定）。

## 运行

1. 构建原生库：

   ```sh
   cd ../../axon
   pwsh ./scripts/build-native.ps1 -Profile release
   cd ../axon-examples/flutter
   ```

2. 用 `--dart-define` 指定 dylib 路径运行（loader 优先用 env/define，其次相对 target 目录）：

   ```sh
   flutter run -d macos --dart-define=AXON_LIB_PATH=$PWD/../../axon/outputs/native/macos/release/libaxon.dylib
   ```

## 测试

```sh
flutter test
```
