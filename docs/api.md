# Axon SDK 接口参考

本页面向 ABI 0.10.x，说明常用接口的职责、跨语言名称和生命周期。Python、Dart 与 .NET 的方法名不同，但都通过同一 Rust/C ABI 运行时工作。Rust 高层 API 单独通过 `axon-api` 提供，不应直接套用绑定的方法名。

本页提供对象模型与跨语言速查；参数、默认值、返回类型和示例见以下手册。所有文档可在本仓库内阅读，无需 SDK 源码。

| 手册 | 内容 |
| --- | --- |
| [Python API](api/python.md) | 创建配置、发现、订阅、滤波与分析、录制、AXF 读写与导出、LSL、健康事件 |
| [Dart/Flutter API](api/dart.md) | 命名参数、Stream 消费、订阅取消、完整模拟采集示例与文件接口 |
| [.NET API](api/dotnet.md) | 配置类型、Device/Session、异步 reader、队列容量、录制、文件与发布 |
| [数据类型与公共约定](api/types.md) | 枚举值、数据布局、分析参数约束、结果字段、状态机和错误码 |

本页中的 `axon`、`session`、`raw`、`pipeline`、`processed` 分别表示已创建的对应对象。直接调用 C ABI 时，使用同版本 SDK 发布包提供的 `axon.h` 声明结构体与函数；本页不是完整 C 头文件替代品。

## 对象与所有权

| 对象 | 职责 | 关闭与释放 |
| --- | --- | --- |
| Axon | provider、设备池、设备查询、模拟器与健康状态 | shutdown 永久关闭运行时，语言层 dispose 释放对象 |
| Session | 绑定一个设备 serial，创建显式流消费者 | 关闭其子订阅与管线的运行时 |
| 原始订阅 | 接收指定流的原始样本与事件 | 可独立录制和发布 LSL |
| ProcessingPipeline | 对一个流建立独立处理分支，持有滤波配置 | 可独立录制和发布 LSL，关闭其处理后订阅 |
| 处理后订阅 | 接收管线样本，配置频谱、信号、认知和质量分析 | 关闭它不等于关闭整条管线 |
| Recording | 持有原始订阅或管线来源，管理文件提交 | 显式 finish 保存，cancel/abort 取消未完成录制 |
| LSL publisher | 独立拥有 outlet、发布状态与计数 | stop 幂等；包装对象仍需释放 |

C 调用方须区分 `close` 与 `free`：前者关闭运行时，后者消费句柄。父对象关闭后，子句柄仍须分别 free。字符串、快照和 AXF 读取结果也使用各自的释放函数，不能混用。

## Axon 与设备查询

| 操作 | Python | Dart | C#/.NET |
| --- | --- | --- | --- |
| 创建 | `Axon(...)` | `Axon(...)` | `new Axon(...)` |
| 启动 | `axon.start()` | `axon.start()` | `axon.Start()` |
| 查询设备 | `axon.devices()` | `axon.devices()` | `axon.Devices()` |
| 查询流 | `axon.device_streams(serial)` | `axon.deviceStreams(serial)` | `device.Streams` |
| 查询通道 | `axon.device_stream_channels(serial, stream_id)` | `axon.deviceStreamChannels(serial, streamId)` | `device.StreamChannels(streamId)` |
| 查询流 metadata | `axon.device_stream_metadata(serial, stream_id)` | `axon.deviceStreamMetadata(serial, streamId)` | `device.StreamMetadata(streamId)` |
| 创建设备会话 | `axon.new_session(serial)` | `axon.newSession(serial)` | `device.OpenSession()` |
| 终态关闭 | `axon.shutdown()` | `axon.shutdown()` | `axon.Shutdown()` |
| 释放 | `axon.dispose()` 或 `with` | `axon.dispose()` | `axon.Dispose()` 或 `using` |

创建选项 `AxonCreateOptions` 选择 provider；Lychee 的传输标志、端口与组播地址放在嵌套的 `LycheeProviderOptions` 中。设备身份描述与流描述分开，采样率、采样模式、通道和单位应从所选流读取。

C 入口包括 `axon_create`、`axon_start`、`axon_shutdown`、`axon_free`、`axon_device_stream_count/info` 与 `axon_session_create`。枚举当前设备可使用 `axon_device_snapshot_create` 及快照查询函数，避免动态设备列表在多次查询间变化。

## 模拟器与回放

| 操作 | Python | Dart | C#/.NET |
| --- | --- | --- | --- |
| 创建模拟器 | `axon.start_simulator(model, serial, custom_options)` | `axon.startSimulator(model: ..., serial: ..., customOptions: ...)` | `axon.AddSimulator(model, serial, customOptions)` |
| 停止 | `simulator.stop()` | `simulator.stop()` | `simulator.Stop()` |

当前 Dart/.NET `DeviceModel` 区分 Lychee BCI100、BCI100-E、BCS100、BCH100 和 Custom。只有 Custom 必须且允许传入自定义选项：可启用 1–64 通道 EEG（250 Hz）、双通道 NIRS（20 Hz），或同时启用，至少启用一种。Lychee 型号采用固定配置和六位十六进制 serial。句柄提供 id、serial、model，stop 幂等。各语言名称见对应接口参考。

C 使用 `axon_simulator_start` / `axon_simulator_stop`。模拟器先注册成设备，再通过普通 Session 读数。

EDF/AXF 回放由 replay provider 提供；Rust 使用 `with_replay_provider()` 注册，再通过 `replay_controller().add_replay(...)` 添加文件。回放设备同样以 serial 查询和打开 Session。厂商控制通过 typed controller 提供，不存在跨厂商的核心通用 `send_command`。

## Session、订阅与处理管线

| 操作 | Python | Dart | C#/.NET |
| --- | --- | --- | --- |
| 原始订阅 | `session.subscribe_raw(stream_id)` | `session.subscribeRaw(streamId)` | `session.GetStream(streamId).Subscribe()` |
| 创建管线 | `session.create_pipeline(stream_id)` | `session.createPipeline(streamId)` | `session.GetStream(streamId).CreatePipeline()` |
| 订阅管线 | `pipeline.subscribe()` | `pipeline.subscribe()` | `pipeline.Subscribe()` |
| 替换滤波链 | `pipeline.replace_filters(stages)` | `pipeline.replaceFilters(stages)` | `pipeline.SetFilters(stages)` |
| 接收样本 | `subscription.data_queue.get(...)` | `subscription.signal.listen(...)` | `subscription.CreateDataReader(...)` |
| 查询来源 | `subscription.source_kind` | `subscription.sourceKind` | `subscription.SourceKind` |

Session 创建时只选择 serial；每次原始订阅或创建管线都显式选择 stream id。一台设备可以有多个订阅与管线。原始数据独立保留，同一管线的滤波配置作用于它的输出，分析和投递配置属于各自订阅。

均匀采样流可建立管线；Motion 或其他不规则流使用原始订阅与录制。滤波参数按所选流的采样率校验，无需在滤波配置中另传一套采样率。

C 创建路径是 `axon_session_subscribe_raw` 或 `axon_session_create_pipeline` → `axon_pipeline_subscribe`。滤波使用 `axon_pipeline_add_filter/replace_filters/clear_filters`；查询来源使用 `axon_subscription_source_kind`。每个订阅只投递其来源的一路 DATA，不能把同一个消息当作原始和处理后数据各消费一次。

## 分析与投递诊断

以下配置作用于处理后订阅 `processed`。

| 分析 | Python | Dart | C#/.NET |
| --- | --- | --- | --- |
| 频谱 | `configure_spectrum(...)` | `configureSpectrum(...)` | `ConfigureSpectrum(...)` |
| 频段功率 | `configure_signal(...)` | `configureSignal(...)` | `ConfigureSignal(...)` |
| 认知指标 | `configure_cognitive(...)` | `configureCognitive(...)` | `ConfigureCognitive(...)` |
| 时间域质量 | `configure_time_quality(...)` | `configureTimeQuality(...)` | `ConfigureQuality(...)` |

Python 通过 `spectrum_queue`、`signal_queue`、`cognitive_queue`、`quality_queue` 接收结果；Dart 对应 `spectrum`、`bandPower`、`cognitive`、`quality` Stream；.NET 对应 `CreateSpectrumReader`、`CreateSignalReader`、`CreateCognitiveReader`、`CreateQualityReader`。

C 使用 `axon_subscription_set_spectrum/signal/cognitive/time_quality`，对应 `clear` 函数关闭分析。配置需要合法窗口与参数，启用后仍需等待足够样本。

消费者速度不足可能导致有界队列丢弃旧消息。Python 队列提供 `dropped_count`，Dart 提供各类 `*DroppedCount`，.NET 提供 `GetManagedDeliveryStats` 和 `GetNativeDeliveryStats`。C 通过 `axon_subscription_stats`、`axon_subscription_kind_stats` 与 `axon_subscription_poll_event` 查询统计和诊断。队列容量、投递丢弃与采集端连续性是不同信息，应一起检查。

## 样本与时间戳

| 字段语义 | Python 示例字段 | 约定 |
| --- | --- | --- |
| 块起始时间 | `start_timestamp` | 绝对 Unix epoch 微秒 |
| 帧数 | `num_samples` | 每通道的样本数，即帧数 |
| 通道数 | `num_channels` | 从流描述读取，不能硬编码 |
| 样本数组 | `data` | 按帧交错，长度为帧数 × 通道数 |
| 不规则帧时间 | `sample_offsets_us` | 相对首帧的微秒偏移，需逐帧保留 |
| 事件时间 | `onset`、`duration` | onset 为绝对 epoch 微秒，duration 为微秒时长 |

均匀流第 `i` 帧时间由起始时间与采样率确定；不规则流第 `i` 帧时间为 `start_timestamp + sample_offsets_us[i]`。样本单位由流与通道描述确定。

## AXF 录制与文件接口

| 操作 | Python | Dart | C#/.NET |
| --- | --- | --- | --- |
| 原始录制 | `raw.start_recording(path, ...)` | `raw.startRecording(path, ...)` | `raw.StartRecording(path, ...)` |
| 处理后录制 | `pipeline.start_recording(path, ...)` | `pipeline.startRecording(path, ...)` | `pipeline.StartRecording(path, ...)` |
| 保存 | `recording.finish()` | `recording.finish()` | `recording.Finish()` |
| 取消未完成录制 | `recording.abort()` | `recording.abort()` | `recording.Abort()` |
| 事件注释 | `recording.push_event(...)` | `recording.pushEvent(...)` | `recording.AddEvent(...)` |

录制来源是具体原始订阅或管线，录制对象独立于显示订阅。开始录制可附带结构化 metadata。保存必须在来源或 Session 关闭前显式执行；关闭来源会取消未完成录制并删除不完整文件。Saved 结果可重复读取，不能通过取消删除。`end_timestamp` 表示时长边界，nullable `last_sample_timestamp` 才是最后实际样本时间。

C 使用 `axon_subscription_recording_start`（仅原始订阅）或 `axon_pipeline_recording_start`；随后使用 `axon_recording_push_event/finish/cancel/state/free`。finish 返回的路径需要 `axon_free_string` 释放。

Python、Dart 与 .NET 提供 `AxfReader` 查询描述、metadata、事件与样本，以及无需 Axon/设备即可写入的 `AxfWriter`。C 对应 `axon_axf_reader_*`、`axon_axf_read_*` 和 `axon_axf_writer_*`。读取结果有独立 free 函数；writer 必须显式 finish，直接关闭 writer 不会自动完成文件，也不会像取消采集录制一样删除文件。

| 导出目标 | Python | Dart | .NET |
| --- | --- | --- | --- |
| 单流 EDF/BDF/CSV | `axon.export_axf_stream(...)` | `axon.exportAxfStream(...)` | `AxfExporter.ExportStream(...)` |
| 整份 XDF | `axon.export_axf_xdf(...)` | `axon.exportAxfXdf(...)` | `AxfExporter.ExportXdf(...)` |
| GB/T 47127 数据集 | `axon.export_axf_gbt47127(...)` | `axon.exportAxfGbt47127(...)` | `AxfExporter.ExportGbt47127(...)` |

AXF 文件流编号是文件内的数值 id，区别于实时流的字符串 stream id；导出前查询文件描述。XDF 为离线转换，无需加载 liblsl，输出路径须不存在。导出时保留流的采样模式、metadata 和不规则帧时间；不要将多流文件当作单流导出。

## LSL publisher

原始订阅和管线分别提供 Python `start_lsl()`、Dart `startLsl()`、.NET `StartLsl()`。C 使用 `axon_subscription_lsl_start` 或 `axon_pipeline_lsl_start`。

发布期间保留 publisher；结束后调用 stop 并释放对象。来源断线或关闭会停止相应发布；Failed 为终态，stop 不清除失败原因。队列溢出报告发布失败，不能静默丢帧。`published_frames` 表示提交给 liblsl 的帧数，不代表接收端确认收到。

保留通道顺序、单位、metadata 与不规则流逐帧时间；epoch 微秒映射到进程共享锚点下的 LSL 时钟，不代表设备时钟校正。当前支持 Windows、Linux、macOS 桌面实时流发布，不支持历史回放发布、LSL 接收或事件标记 outlet。部署时将发布包中的 liblsl 与许可证文件保留在 Axon 原生库同一目录，详见[运行库准备](getting-started.md#准备语言包与运行库)。

## 传输健康状态

| 操作 | Python | Dart | C#/.NET |
| --- | --- | --- | --- |
| 一致快照 | `axon.health_snapshot()` | `axon.healthSnapshot()` | `axon.GetHealthSnapshot()` |
| 状态通知 | `axon.set_transport_status_callback(...)` | `axon.transportStatus` | `axon.TransportStatusChanged` |

状态为 Healthy、Degraded、Failed，按 provider 下的 Network、Usb、Serial、Ble 类别独立报告；这些类别不同于 Lychee 的 TCP/UDP 配置标志。未启用或未报告的类别缺席。部分类别失败时其他类别仍可工作；传输健康通知不会替代设备 Connected/Disconnected 事件。

先注册通知，再启动或读取快照。通知不回放启动事件，快照是查询当前状态的依据；通知和快照之间不构成原子事务。语言层快照复制数据，可在父对象释放后继续读取；shutdown 后不能创建新快照。

C 使用 `axon_health_snapshot_create/summary/provider/category/free` 与 `axon_set_transport_status_callback`。初始化带 size/version 的 DTO 时使用发布包头文件中的 INIT 宏；借用字符串仅在对应快照或回调有效期内可用。健康快照独立持有数据，使用后调用 `axon_health_snapshot_free`；普通状态回调中的内容应在回调返回前复制。

## 错误与线程

C 以 `AxonResult` 返回错误，创建失败通过独立 `out_error` 返回诊断，使用 `axon_free_string` 释放。已有句柄通过各自 `last_error_copy` 查询，先获取所需长度再复制。Python 抛出 `AxonError` 等异常，Dart 抛出 `AxonException` 等异常，.NET 抛出 `AxonException` 等异常。

C/Python 用户回调通常运行在原生工作线程，指针只在回调期间有效；回调中复制必要信息、交给应用队列，避免重入 SDK。.NET 传输健康事件在托管 worker 上投递，允许查询与释放，handler 异常隔离。Dart 使用异步桥接投递到 isolate。UI 操作仍需遵循各框架线程规则。

## 查看参数与类型

Python 可以直接查看已安装包的接口说明：

```python
from axon import Axon, AxonSession, ProcessingPipeline

help(Axon)
help(AxonSession.subscribe_raw)
help(ProcessingPipeline.start_recording)
```

Dart 和 .NET 可在 IDE 中查看安装包的公开类型与方法签名。C 调用方使用发布包的 `axon.h`，保持头文件与动态库版本一致；不要自行猜测结构体布局或函数签名。

返回[SDK 概览](overview.md)、[接入指南](getting-started.md)或[仓库首页](../README.md)。
