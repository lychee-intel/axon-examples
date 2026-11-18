# Python API 手册

适用于 ABI 0.10.x 的 `axon` 包。下列签名中的返回类型用于说明；无显式返回值的方法返回 `None`。先按[接入指南](../getting-started.md)安装平台匹配的 wheel，再使用本页。公共数据布局、状态和错误码见[数据类型与约定](types.md)。

## Axon 创建配置

```python
Axon(lib_path=None, options=None)
AxonCreateOptions(provider_flags=3, lychee=LycheeProviderOptions())
LycheeProviderOptions(
    transport_flags=15, tcp_port=31200, udp_port=31300,
    multicast_port=31400, multicast_group=None,
)
```

`lib_path` 可显式指定原生库路径；省略时由包的加载机制定位。`options=None` 使用默认配置。创建成功返回尚未启动的 Axon；加载或原生创建失败抛 `OSError`，错误选项还可能抛 `ValueError` / `TypeError`。

| 参数 | 默认值 | 含义 |
| --- | --- | --- |
| provider_flags | 3 | Lychee=1、Custom simulator=2，按位或组合 |
| transport_flags | 15 | TCP=1、UDP=2、multicast=4、mDNS=8，按位或组合 |
| tcp_port / udp_port / multicast_port | 31200 / 31300 / 31400 | 对应监听端口，uint16 范围 |
| multicast_group | None | 采用协议默认组播地址；显式值不能含 NUL |

这些 transport_flags 描述 Lychee 网络配置，不是 Network/Usb/Serial/Ble 健康类别的位图。只使用 Custom 模拟器时可设置 `provider_flags=2`，同时将 Lychee `transport_flags=0`，避免启动网络监听。

```python
from axon import Axon, AxonCreateOptions, LycheeProviderOptions

options = AxonCreateOptions(
    provider_flags=2,
    lychee=LycheeProviderOptions(transport_flags=0),
)
with Axon(options=options) as axon:
    axon.start()
```

`start()` 启动发现和 provider；`shutdown()` 永久关闭运行时，之后不能再次 start；`dispose()` 释放实例且幂等。`with Axon()` 只管理释放，仍需显式 start。

`axon.log_init(level, log_path=None)` 初始化进程级原生日志，level 使用 `LogLevel`：TRACE、DEBUG、INFORMATION、WARNING、ERROR、CRITICAL、NONE；None 路径写 stderr。不要把日志配置当作每个 Session 独立设置。

## 设备发现与描述

| 签名 | 返回值 | 说明 |
| --- | --- | --- |
| `devices()` | `list[DeviceInfo]` | 一份设备快照；无设备时为空列表 |
| `device_info(serial)` | `DeviceInfo` | 查询已连接设备身份 |
| `device_streams(serial)` | `list[DeviceStreamInfo]` | 查询流及其 metadata |
| `device_stream_channels(serial, stream_id)` | `list[DeviceStreamChannelInfo]` | 按流顺序返回通道 |
| `device_stream_metadata(serial, stream_id)` | `dict` | 返回复制后的扩展 metadata |
| `wait_for_device(timeout=None)` | `str` | 等待设备上线，返回 serial；timeout 单位秒，None 无限等待 |
| `set_device_callback(callback)` | None | 替换设备通知回调；None 清除 |

设备查询与打开 Session 之间可能发生断线，调用方仍需捕获 AxonError。`wait_for_device` 会使用设备回调注册槽并尝试启动运行时；不要与自定义设备回调并用，也不要用它替代现有设备快照查询。已有设备先调用 `devices()`；等待超时抛 `TimeoutError`。

设备回调签名为 `callback(serial, name, firmware_version, connected)`，connected 为 bool。回调在原生工作线程执行，只把信息交给应用队列；流查询、关闭对象和 UI 操作放在消费线程。

```python
from queue import Queue
from axon import Axon

changes = Queue()
with Axon() as axon:
    axon.set_device_callback(
        lambda serial, name, firmware, connected:
            changes.put((serial, connected))
    )
    axon.start()
    # 应用在主线程或独立消费者中读取 changes，再查询流或更新 UI。
    print(axon.devices())
    axon.set_device_callback(None)
```

## 模拟器

`axon.start_simulator(model, serial, custom_options=None) -> Simulator` 要求 Axon 已启动。Simulator 的只读属性为 `id`、`serial`、`model`；`stop()` 幂等，支持 with。

| model | custom_options | serial |
| --- | --- | --- |
| `DeviceModel.LYCHEE_BCI100` | 必须省略 | 六位十六进制，返回时规范化为大写；3 通道 EEG |
| `DeviceModel.LYCHEE_BCI100_E` | 必须省略 | 同上；3 通道 EEG、双通道 NIRS |
| `DeviceModel.LYCHEE_BCS100` | 必须省略 | 同上；单通道 EEG |
| `DeviceModel.LYCHEE_BCH100` | 必须省略 | 同上；32 通道 EEG |
| `DeviceModel.CUSTOM` | 必须提供 | 1–64 个 ASCII 字母、数字、点、下划线或短横线 |

`CustomSimulatorOptions(eeg_channels=None, nirs_enabled=False)`：EEG 通道为 1–64，或 None 表示关闭；NIRS 为双通道，bool 开关。至少启用一种。EEG 固定 250 Hz，NIRS 固定 20 Hz。serial 必须在当前设备池内唯一。

## Session 与订阅

```text
axon.new_session(serial) -> AxonSession
session.subscribe_raw(stream_id, *, delivery_mask=DeliveryKinds.ALL, attach=True)
session.create_pipeline(stream_id) -> ProcessingPipeline
pipeline.subscribe(*, delivery_mask=DeliveryKinds.ALL, attach=True)
```

`subscribe_raw` 返回 RawSubscription，`pipeline.subscribe` 返回 ProcessedSubscription。`stream_id` 使用查询到的流 id。未知设备/流、关闭后的来源会报错；不规则流不能创建处理管线。

`delivery_mask` 选择跨语言投递的消息种类；`attach=True` 自动安装 Python 数据桥接。`attach=False` 不向 Python 队列推送消息，适用于仅录制/发布等不需要 Python 消费的情况；此时不要等待 data_queue。

Session、pipeline 和 subscription 都支持 `close()`、`dispose()` 与 with：close 关闭运行时但保留包装句柄；dispose 释放包装句柄。建议使用 with，按子到父顺序退出。

| 属性/方法 | 返回值或行为 |
| --- | --- |
| `subscription.source_kind` | `SubscriptionSourceKind.RAW` 或 PROCESSED |
| `data_queue` | SampleBlock，原始或处理后由 source_kind 决定 |
| `event_queue` | AxonEvent 实验注释 |
| `spectrum_queue` | SpectrumBlock |
| `signal_queue` | SignalBlock 频段功率 |
| `cognitive_queue` | CognitiveMetrics |
| `quality_queue` | TimeQualityResult |
| `on_data(callback)` / `on_event(callback)` | 同步原生回调，分别接收已复制的 block/event |
| `stats` | SubscriptionStatistics，注意它是属性而非方法 |
| `delivery_stats(kind)` | DeliveryKindStatistics，kind 为消息编号而非 mask |
| `poll_events(max_events=64)` | 诊断列表，max_events 为 1–256；无事件返回空列表 |

样本队列容量为 256 个 block；其他队列为 64 项。满时丢弃最旧项，可查询 `queue.dropped_count`。`get(timeout=...)` 的超时单位为秒，抛 `queue.Empty`；这表示本次没有取到结果，不直接等于设备断线。耗时用户回调会延迟原生线程，通常优先消费队列。

## 滤波与分析

`pipeline.add_filter(stage)` 追加一个阶段；`replace_filters(stages)` 原子替换完整有序链，失败保留旧链；`clear_filters()` 清空。

```python
AxonFilterStageConfig(
    filter_type, kind, cutoff_hz, cutoff2_hz=0.0, order=4, q=0.0,
)
```

filter_type 使用 `FilterType.FIR/IIR`；kind 使用 `FilterKind.LOW_PASS/HIGH_PASS/BAND_PASS/BAND_STOP/NOTCH`。cutoff 单位 Hz，带通/带阻需同时设置低、高截止频率；按所选流采样率校验。

以下签名仅用于 ProcessedSubscription，返回 None：

```python
processed.configure_spectrum(fft_size=1024, hop=None)
processed.configure_signal(fft_size=1024, hop=None, selected_channel=0)
processed.configure_cognitive(
    alpha=0.15, range_min=0, range_max=3,
    attention_median_window=3, fft_size=256, hop=128, selected_channel=0,
)
processed.configure_time_quality(
    min_samples=2, flatline_delta=1e-6,
    clip_limits=None, transient_delta=None,
)
```

hop 为帧数；频谱/频段功率的 None 采用半窗口。`clip_limits` 为 `(low, high)` 二元组，None 不启用削波边界。`clear_spectrum/signal/cognitive/time_quality()` 分别停用对应分析。各约束与返回字段见[分析约定](types.md#分析参数与结果)。

下面是完整的无硬件滤波、频谱与处理后录制示例。输出目录需存在，`filtered.axf` 为应用选择的输出文件。

```python
from axon import (
    Axon, AxonCreateOptions, LycheeProviderOptions,
    DeviceModel, CustomSimulatorOptions,
    AxonFilterStageConfig, FilterType, FilterKind,
)

options = AxonCreateOptions(
    provider_flags=2, lychee=LycheeProviderOptions(transport_flags=0),
)
with Axon(options=options) as axon:
    axon.start()
    with axon.start_simulator(
        DeviceModel.CUSTOM, "analysis-demo", CustomSimulatorOptions(eeg_channels=2),
    ) as simulator:
        with axon.new_session(simulator.serial) as session:
            with session.create_pipeline("eeg") as pipeline:
                pipeline.replace_filters([
                    AxonFilterStageConfig(
                        FilterType.IIR, FilterKind.BAND_PASS,
                        cutoff_hz=0.4, cutoff2_hz=40, order=2,
                    ),
                ])
                with pipeline.subscribe() as processed:
                    processed.configure_spectrum(fft_size=256, hop=128)
                    with pipeline.start_recording("filtered.axf") as recording:
                        spectrum = processed.spectrum_queue.get(timeout=10)
                        print(spectrum.channel_index, spectrum.frequencies)
                        print(recording.finish())
```

## RecordingHandle

`raw.start_recording(path, metadata=None)` 或 `pipeline.start_recording(path, metadata=None)` 返回 RecordingHandle。metadata 可为结构化 dict 或 JSON 字符串；None 使用默认值。不能从处理后订阅创建录制。

| 接口 | 返回值与约束 |
| --- | --- |
| `state` | int，1 Active / 2 FinalizationFailed / 3 Saved / 4 Cancelled |
| `push_event(onset, duration, event_type, description="")` | None；onset 为 epoch 微秒，duration 非负 |
| `finish()` | 录制结果 dict，字段见公共约定；需在来源关闭前调用 |
| `abort()` / `cancel()` | 取消未完成录制；不用于删除已保存文件 |
| `dispose()` | 释放，未完成录制被取消；with 退出调用它 |

原始来源关闭会取消其录制；处理后显示订阅关闭不会取消 pipeline 录制。保存成功后可重复 finish 读取结果，但 RecordingHandle 本身仍须处于未 dispose 状态。

## AxfReader

| 签名 | 返回值 | 行为 |
| --- | --- | --- |
| `AxfReader.open(path, lib_path=None)` | AxfReader | 无需创建 Axon，打开失败抛 OSError |
| `info()` | AxfInfo | 文件版本、时间范围、块/帧数、流和 metadata |
| `read_events()` | list[AxfEvent] | 复制的文件事件 |
| `verify()` | bool | 检查文件；操作或解码错误也可能抛 OSError |
| `read_block(timestamp)` | AxfBlock | 首个起始时间恰好匹配的块 |
| `read_block_by_index(index)` | AxfBlock | 零起始逻辑块索引，保留重复时间戳 |
| `read_range(start, end)` | list[AxfBlock] | 起始时间在 `[start,end)` 的完整块 |
| `read_blocks(start, end, batch_size=64)` | iterator[AxfBlock] | 有界批次遍历完整块，batch_size 必须为正 |
| `close()` | None | 幂等释放，也支持 with |

reader 返回的内容已复制，不依赖临时原生结果。对同一 reader 串行执行读取、迭代和 close；大文件优先 read_blocks，避免一次分配所有块。AxfBlock 的 stream_id 为文件内数值 id，数据布局同 SampleBlock。

```python
from axon import AxfReader

with AxfReader.open("filtered.axf") as reader:
    info = reader.info()
    for stream in info.streams:
        print(stream.id, stream.name, stream.channels)
    for index in range(info.total_blocks):
        block = reader.read_block_by_index(index)
        print(block.stream_id, block.num_samples)
    print(reader.read_events())
```

## 独立 AxfWriter

`AxfWriter.create(path, streams, options=None, lib_path=None)` 创建并截断目标文件，父目录必须存在。streams 为非空 AxfStreamDefinition 集合；id 为唯一 uint16。无需 Axon 或 Session。

```python
AxfChannelDefinition(name, label, unit, channel_type=AxfChannelType.EEG, gain=1.0)
AxfStreamDefinition(
    id, name, sample_rate_hz, channels, kind=0, sampling_mode=0,
    metadata=None, vendor_kind=None,
)
AxfWriterOptions(
    start_timestamp=0, device_info=None, metadata=None,
    compression=AxfCompression.ZSTD, sample_format=AxfSampleFormat.F32,
    physical_range=None,
)
```

writer metadata 为 `dict[str,str]`，区别于采集录制的结构化 metadata。compression 为 LZ4/ZSTD；sample_format 为 F32/I16/I24/ADAPTIVE，physical_range 为可选物理量化范围。使用量化时应按信号单位设置合理范围。

`write_block(stream_id, start_timestamp, num_frames, samples, sample_offsets_us=None)` 写入按帧交错数组；num_frames 必须为正，samples 长度须等于帧数×通道数。不规则流必须有逐帧偏移；均匀流省略。`push_event(onset,duration,event_type,description=None)` 写事件。`flush()` 刷出待写数据但不结束文件；`finish()` 完成索引/Footer，成功后幂等；`close()` / `dispose()` 只释放，支持 with。

```python
from axon import AxfWriter, AxfWriterOptions, AxfStreamDefinition, AxfChannelDefinition

start = 1_800_000_000_000_000
streams = [AxfStreamDefinition(
    id=1, name="eeg", sample_rate_hz=250,
    channels=[AxfChannelDefinition("C1", "C1", "uV")],
)]
with AxfWriter.create("offline.axf", streams, AxfWriterOptions(start_timestamp=start)) as writer:
    writer.write_block(1, start, 3, [1.0, 2.0, 3.0])
    writer.push_event(start, 0, "start", "offline example")
    writer.finish()
```

## 导出

| 签名 | 说明 |
| --- | --- |
| `axon.export_axf_stream(axf_path, stream_id, output_path, format="edf")` | stream_id 为文件内数值，format 为 `edf`、`bdf`、`csv` |
| `axon.export_axf_xdf(axf_path, output_path)` | 整份多流录制转 XDF；输出文件须不存在，不依赖 liblsl |
| `axon.export_axf_gbt47127(axf_path, dataset_dir, progress=None)` | 导出数据集，progress 为同步 `(phase, completed, total)` 回调 |

这些方法同步执行，返回 None。不要在 UI 线程上运行大型导出；progress 回调不可重入同一 Axon。非法格式在包装层报 ValueError，文件和转换错误抛 AxonError。单流导出对采样模式、通道与目标格式的兼容性仍有要求。

## LSL 与健康状态

`raw.start_lsl(options=None)` / `pipeline.start_lsl(options=None)` 返回 LslPublisher。`LslPublishOptions(name=None, queue_capacity=64)` 中 name 为可选非空白名称，queue_capacity 必须是正整数，单位为块队列容量。名称省略使用默认值。运行库缺失、不支持的来源和创建失败会报错。

publisher 的 `status` 返回 LslPublishStatus，包含 state（RUNNING/STOPPED/FAILED）、name、logical_id、source_id、published_frames、rejected_blocks、error。调用 `stop()` 停止，`dispose()` 释放，支持 with；FAILED 原因不会被 stop 清除。使用前按[部署说明](../getting-started.md#准备语言包与运行库)放置 liblsl。

```python
from queue import Queue
from axon import Axon

changes = Queue()
with Axon() as axon:
    axon.set_transport_status_callback(changes.put)
    axon.start()
    snapshot = axon.health_snapshot()
    for provider in snapshot.providers:
        print(provider.provider_id, provider.health, provider.categories)
    axon.set_transport_status_callback(None)
```

`health_snapshot()` 返回不可变 HealthSnapshot；`set_transport_status_callback(callback)` 的参数为接收单个 TransportStatusEvent 的 callable，None 清除。回调只排队，不能调用 SDK。快照独立拥有数据，shutdown 后不能新建；类别缺席表示未报告，不能补成 Failed。

返回[接口总览](../api.md)。
