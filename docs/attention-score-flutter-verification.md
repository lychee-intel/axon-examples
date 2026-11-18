# Flutter 注意力分数验证记录

日期：2026-11-18。实现见 [设计](attention-score-flutter-design.md)。

## 已验证

- Flutter `analyze` 无问题；`flutter test` 17 项通过；Windows Debug 应用构建成功。MSBuild 报告原有 Flutter wrapper 共享中间目录警告 MSB8028。
- Dart `analyze` 无问题；完整串行测试开启 `AXON_DART_ATTENTION_NATIVE_TEST=1`，113 项通过、2 项原有可选测试跳过。包含原生模拟器完整两秒窗口收分、清除、关闭后拒绝操作和 DTO 解码。
- `cargo test --workspace` 通过；新增原生接口包含评分、伪迹保持、事件排序、参数/布局校验、清除/重配和父对象关闭测试。
- 真实评分工作线程积压回归测试先失败再通过：输入队列溢出改为失败策略，轮询收到失败并丢弃失效分数。
- Flutter 窗口缺失后伪迹保持回归测试先失败再通过，等待新有效值后才恢复数字读数。
- MSVC C11 `/W4` 头文件检查、axon-ffi Clippy（warnings denied）、rustdoc 和两个仓库 `git diff --check` 通过。
- Python 兼容性测试最终完整串行重跑：120 项与 10 个 subtests 通过。首次运行有 3 项协议模拟器 TCP 监听器启动失败；在其他测试进程结束后完整重跑通过，未修改 Python 代码。
- .NET 8 / 9 / 10 的兼容性测试均通过，每个平台 183 项；原有 DeviceTests 的 xUnit1031 警告仍在。
- 桌面实际验证等待窗口、BCI100 模拟器的伪迹保持、停止后保留曲线。用户按 Escape 终止桌面操作后，没有继续控制窗口。新增“EEG 分数模拟器”已编译并通过 Flutter 测试，正常数值曲线的最终桌面验收留给用户。

## 环境与复现

本机原有 `flutter/pubspec_overrides.yaml` 指向旧 vendor SDK，现已改为相邻源码绑定以联调新增接口；原配置备份在 Git 忽略的 `target/attention-preview/pubspec_overrides.before.yaml`。发布的旧 0.10.0 包不含新接口，需要匹配此次源码构建的动态库。

```powershell
cd D:\code\Rust\axon-examples\flutter
$env:AXON_LIB_PATH = 'D:\code\Rust\axon\outputs\native\windows\debug\axon.dll'
flutter run -d windows
```

选择“EEG 分数模拟器”，点击“开始”，切换到“注意力分数”。原 BCI100 协议模拟器信号会触发幅值伪迹判定，因此另提供 SDK 自定义 EEG 模拟器供正常数值预览；没有在示例中修改评分算法或缩放真实设备数据。

Python/C# 示例尚未同步。macOS/Linux 和真实设备未验证。
