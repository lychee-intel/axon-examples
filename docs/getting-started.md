# Axon SDK 接入指南

本文以当前 ABI 0.10.x 的语言绑定说明接入步骤。先准备匹配的语言包与原生库，再使用模拟器验证订阅，最后接入真实设备或处理、录制分支。GUI 示例的依赖说明见[仓库首页](../README.md#版本兼容)。

## 准备语言包与运行库

使用 SDK 发布包中的语言绑定与原生库，无需检出 SDK 源码。选择与你的操作系统和 CPU 架构匹配的文件，语言包与原生库应来自同一版发布。

| 语言 | 安装方式 |
| --- | --- |
| Python | 在虚拟环境中安装发布的 `.whl` 文件，例如 `python -m pip install ./packages/<wheel文件名>.whl`，将占位文件名替换为实际文件名 |
| C#/.NET | 将发布的 `.nupkg` 放入本地 NuGet 源，配置包源并引用对应版本的 `Axon` 包 |
| Dart/Flutter | 两种方式：通过自建 Pub 仓库的 hosted 依赖拉取绑定，或解压 SDK ZIP 后通过 path 引用；再运行 `flutter pub get`。详见 [Flutter 接入说明](../flutter/README.md) |

Flutter 示例默认保留相邻源码依赖用于联调；使用已交付 SDK 时，通过 `pubspec_overrides.yaml` 选择 Pub 或压缩包方式。当前 Pub 包仅含 Dart 绑定，仍需匹配的原生库；Gitea 下载地址的网络限制见 Flutter 接入说明。.NET 项目若配置了源码项目引用，应改为发布的 NuGet 包引用。当前示例的版本差异见[版本兼容说明](../README.md#版本兼容)。

需要单独部署原生库时，保留发布包提供的目录内容。LSL 发布需要同目录的 liblsl 和 `LSL-*.txt` 许可证文件，不能只复制 Axon 动态库。

| 平台 | Axon 原生库 | 同目录的 LSL 运行库 |
| --- | --- | --- |
| Windows | `axon.dll` | `lsl.dll` |
| Linux | `libaxon.so` | `liblsl.so` |
| macOS | `libaxon.dylib` | `liblsl.dylib` |

Python 开发时可通过 `AXON_LIB_PATH` 指定原生库；Flutter 示例通过同名 `--dart-define` 传入。普通 Python wheel 用户通常无需设置路径。

例如，将 Windows 原生库发布包解压到应用的 `native` 目录后，在应用根目录的 PowerShell 中设置 Python 使用的原生库：

```powershell
$env:AXON_LIB_PATH = (Resolve-Path ./native/axon.dll).Path
```

## 采集流程

1. 创建 `Axon`，按需配置 provider 和传输，然后启动。
2. 查询设备或等待上线。BLE 设备需先扫描并显式连接；模拟器先通过对应接口注册。
3. 从设备的流描述读取 stream id、采样模式、采样率、通道和单位。
4. 用 serial 创建 Session。Session 只绑定设备，不会自动选择流。
5. 显式创建原始订阅，或针对均匀采样流创建处理管线并订阅输出。
6. 消费样本、事件与分析结果，按需启动录制或 LSL 发布。
7. 保存录制后，停止发布并依次释放订阅、管线、Session、模拟器和 Axon。

```text
Axon → 设备 serial → Session
                      ├─ 原始订阅(stream id) → 原始样本 / 录制 / LSL
                      └─ 处理管线(stream id) → 滤波输出 / 录制 / LSL
                                              └─ 处理后订阅 → 样本 / 分析
```

## 无硬件 Python 示例

安装当前 ABI 0.10.x 的 Python 包并准备好运行库后，下面的完整代码创建双通道 Custom EEG 模拟器，读取三个数据块并保存 AXF。`sample.axf` 应使用新的输出路径。

```python
from axon import Axon, CustomSimulatorOptions, DeviceModel

with Axon() as axon:
    axon.start()
    with axon.start_simulator(
        DeviceModel.CUSTOM,
        "sdk-demo",
        CustomSimulatorOptions(eeg_channels=2, nirs_enabled=False),
    ) as simulator:
        print(axon.device_streams(simulator.serial))
        with axon.new_session(simulator.serial) as session:
            with session.subscribe_raw("eeg") as raw:
                with raw.start_recording("sample.axf") as recording:
                    for _ in range(3):
                        block = raw.data_queue.get(timeout=5)
                        print(block.start_timestamp, block.num_samples)
                    result = recording.finish()
                    print(result)
```

这里的 `eeg` 来自 Custom EEG 模拟器的已知配置；接入真实设备时应先查询流再选择。队列超时会抛出异常，退出上下文时清理资源；若尚未 `finish()`，录制会被取消。

## 添加处理与分析

以下片段放在已有 `session` 的作用域内，针对其均匀采样 EEG 流创建独立分支。即使同时有原始订阅，该管线也不会修改原始数据。

```python
with session.create_pipeline("eeg") as pipeline:
    # 如需滤波，在此通过 add_filter / replace_filters 配置管线。
    with pipeline.subscribe() as processed:
        processed.configure_spectrum(fft_size=1024)
        spectrum = processed.spectrum_queue.get(timeout=10)
        print(spectrum.frequencies)
```

频谱等分析需要积累足够样本。分析配置属于处理后订阅，滤波配置属于管线；保存处理后数据使用 `pipeline.start_recording(...)`。各语言对应方法见[接口参考](api.md)。

## 生命周期与故障排查

- **保存录制**：在关闭来源前调用 `finish()`；`dispose`、Session 关闭和 Axon 退出不能替代保存动作。
- **停止显示**：取消 UI 消费不会自动等同于停止所有录制和 publisher；显式管理各对象。
- **回调线程**：Python/C 原生回调中只复制数据或放入应用队列，不重入 SDK；UI 更新切换到对应 UI 线程。
- **启动失败或部分传输不可用**：读取传输健康快照与诊断信息。部分传输失败时其他类别可能仍可采集，不能仅依靠设备上线事件判断运行时健康。
- **数据不连续**：检查投递丢弃计数、诊断事件、消费者处理速度与采样模式；收到一个 block 不代表中间没有丢帧。
- **无法加载原生库或 ABI 不匹配**：检查平台、架构、绑定版本与实际加载路径，尤其是 `AXON_LIB_PATH` 是否指向旧文件。

`shutdown()` 是 Axon 的终态操作，之后不能再次启动该实例；需要重新启动时创建新的 Axon。

继续阅读：[接口参考](api.md)、[Python 示例](../python/README.md)、[Flutter 示例](../flutter/README.md)、[.NET 示例](../dotnet/README.zh-CN.md)。
