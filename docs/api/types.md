# 数据类型与公共约定

适用于 ABI 0.10.x。字段名在此主要使用 Python 风格；各语言的实际命名见 [Python](python.md)、[Dart](dart.md)、[.NET](dotnet.md) 手册。时间戳均为 Unix epoch 微秒，频率为 Hz，通道索引从 0 开始。

## 设备与流

`DeviceInfo` 表示设备身份，包含 serial、名称、厂商、固件与硬件版本、能力标志。能力标志不等于某个厂商控制方法一定通过语言绑定暴露；通用 Session 不提供连接或厂商命令操作。

| DeviceStreamInfo 字段 | 类型 | 含义 |
| --- | --- | --- |
| `id` | string | 实时订阅使用的流标识，例如 `eeg`、`nirs`，以设备实际查询为准 |
| `display_name` | string | 展示名称，不作为订阅标识 |
| `kind` | enum/int | 信号种类，见下表 |
| `availability` | enum/int | 当前流可用性；描述存在不等于持续有数据 |
| `sample_rate_hz` | float | 均匀流采样率；不规则流不能据此推算实际帧时间 |
| `num_channels` | int | 通道数 |
| `sampling_mode` | enum/int | Uniform=0，Irregular=1 |
| `metadata` | string map | provider 提供的流扩展描述，允许未知键 |

`DeviceStreamChannelInfo` 包含 `name`、`label`、`unit`、`gain`。按流查询通道，并保持返回顺序；不要把所有数值默认当作微伏。

| 流 kind | C ABI 数值 |
| --- | --- |
| EEG / EMG / ECG / EOG / PPG | 0 / 1 / 2 / 3 / 4 |
| IMU / Impedance / NIRS / Motion | 5 / 6 / 7 / 9 |
| Vendor | 255 |

## SampleBlock 与事件

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `start_timestamp` | int64 | 首帧的绝对时间 |
| `sample_rate_hz` | float | 流采样率 |
| `num_channels` | int | 通道数 C |
| `num_samples` | int | 帧数 N，每帧含 C 个样本 |
| `data` | float 数组 | 长度 N×C，按帧交错 |
| `stream_id` | string | 来源实时流 id |
| `sample_offsets_us` | uint64 数组或空 | 不规则流逐帧相对首帧的微秒偏移 |
| `sequence` | uint64 | 投递序号，用于连续性诊断 |
| `sequence_saturated` | bool | 序号是否已饱和；为 true 时不能继续依赖递增判断 |

例如两通道三帧 `[a0, b0, a1, b1, a2, b2]` 中，第 i 帧第 j 通道是 `data[i*C+j]`。均匀流第 i 帧时间约为 `start_timestamp + i*1_000_000/sample_rate_hz`，转换为整数微秒时需处理舍入；不规则流使用 `start_timestamp + sample_offsets_us[i]`。

`AxonEvent` 包含 `onset`、`duration`、`event_type`、`description`；onset 是绝对时间，duration 是非负微秒时长。不要传入从实验开始计时的相对秒数。

## 滤波参数

| 参数 | 含义与约束 |
| --- | --- |
| filter type | FIR=0、IIR=1，表示实现类型 |
| kind | LowPass=0、HighPass=1、BandPass=2、BandStop=3、Notch=4 |
| cutoff | 截止频率；带通/带阻还需第二截止频率，低端须小于高端 |
| order | 阶数，具体有效范围由对应滤波实现校验 |
| q | 陷波等滤波器使用的品质因数；不用于表示频率 |

频率必须为有限值并符合所选流的 Nyquist 限制（采样率的一半）。用合法的明确参数构造滤波器，不把默认零截止频率当作可用配置。`replace_filters` / `replaceFilters` / `SetFilters` 按顺序应用整条链；替换失败保留原链。

## 分析参数与结果

分析在处理后订阅上配置，要求均匀采样。频段功率和认知分析还要求 EEG kind；对其他 kind 返回 Unsupported。成功替换配置会重置对应分析器历史，配置失败保留原分析器。同一管线的不同订阅可以使用不同分析参数。

| 参数 | 含义 |
| --- | --- |
| FFT size | 窗口帧数，至少为 2 且为 2 的幂 |
| hop | 相邻窗口之间的帧数，必须为正且不超过窗口 |
| selected channel | 要分析的通道，满足 `0 <= index < channel_count` |
| alpha | 认知指标平滑参数 |
| range min / max | 认知指标归一化范围，需有限且 min < max |
| attention median window | 注意力中值平滑窗口，正奇数；1 关闭中值平滑 |
| min samples | 时间域质量计算所需的最低样本数 |
| flatline delta | 平直判断的变化阈值 |
| clip low / high | 可选削波上下界，必须一起提供，low < high |
| transient delta | 可选瞬变阈值 |

`SpectrumBlock` 返回 `start_timestamp`、`sample_rate_hz`、`fft_size`、`channel_index`、`num_bins`、`frequencies`、`bins` 等信息。频率轴单位为 Hz，按结果的通道索引和频点数解读，不把频谱数组当作时域样本。

`SignalBlock.powers` 按 `BAND_NAMES` 顺序排列：Delta、Theta、Alpha、Beta、LowerGamma、HigherGamma、SMR。结果含 `selected_channel` 和时间戳；不要将第 i 个频段误当作第 i 个通道。

`CognitiveMetrics` 含 `focus`、`calm`、`sqi`、`attention_index`、`attention_index_smoothed`、`selected_channel`、时间戳。保留原始与平滑注意力值的区别。

`TimeQualityResult` 按通道输出样本数、非有限值比例、最小/最大值、峰峰值、RMS、方差、平直/削波/瞬变比例、robust deviation、flags 和 hard_fail。质量指标用于描述输入与计算状态，不应将一个标志直接解释为设备断开。

## 投递 mask 与统计

Python `DeliveryKinds`、Dart `axonDelivery*` 和 .NET `DeliveryKinds` 是位掩码。C ABI 的各位为：DATA=`1<<1`、EVENT=`1<<2`、SPECTRUM=`1<<3`、SIGNAL=`1<<4`、COGNITIVE=`1<<7`、QUALITY=`1<<8`。ALL 是这些位的或；启用分析不自动绕过投递 mask。

原始来源 kind=1，处理后来源 kind=2。一个订阅只有一路 DATA，其含义由来源决定。

原生每类投递统计包含 attempted、delivered、overflow_dropped、detach_discarded、counters_saturated。`delivered` 不等于 UI 已显示，也不等于下游已保存。`delivery_stats(kind)` 的 kind 是消息种类编号（1、2、3、4、7、8），**不是位掩码**；例如查询 DATA 传 1，而非 `DeliveryKinds.DATA` 的值 2。

诊断事件中的可选字段由 `optional_fields` 指示有效性，不能将未设置字段的零值当作真实时间戳或丢失序号。poll 接口消费诊断队列，区别于实验注释事件。

## 录制结果与状态

| 状态 | 值 | 调用方处理 |
| --- | --- | --- |
| Active | 1 | 继续录制、finish 或 abort |
| FinalizationFailed | 2 | 保存失败，保留诊断并按错误原因处理 |
| Saved | 3 | 文件已保存；重复 finish 读取缓存结果，不可 cancel 删除 |
| Cancelled | 4 | 未完成录制已取消 |

finish 返回 path、duration_us、total_samples、num_channels、sample_rate_hz、start_timestamp、end_timestamp、last_sample_timestamp。`end_timestamp` 为时长边界，可能包含最后一帧的周期；`last_sample_timestamp` 是最后实际样本的时间，空录制为 null。Dart 的 duration 包装为 `Duration`。

采集录制关闭来源或释放未完成录制会取消并删除不完整输出。**独立 AxfWriter 不同**：释放只关闭资源，不 finish，也不删除文件；必须显式 finish 写入正常索引与 Footer。

AXF 读取范围 `[start, end)` 按块起始时间筛选完整块，不按范围裁剪块内样本。按 timestamp 读取遇到相同起始时间只返回第一块；需要保留重复时间戳或多流块时，按 index 或批次遍历。文件内 stream id 为 uint16，区别于实时流的字符串 id。

## 错误码

| C AxonResult | 值 | 常见原因与处理 |
| --- | --- | --- |
| OK | 0 | 成功 |
| INVALID_ARGUMENT | 1 | 参数、配置或结构头不合法；修正输入 |
| NOT_FOUND | 2 | serial、stream id 或块索引不存在；重新查询 |
| UNSUPPORTED | 3 | 流种类、采样模式或操作不支持；选择兼容来源 |
| IO | 4 | 文件、设备、运行库或传输操作失败；检查诊断与环境 |
| INTERNAL | 5 | 内部运行时错误；保留日志与上下文 |
| INVALID_STATE | 6 | 对象已关闭、Axon 已 shutdown 或状态不允许该操作 |

语言包装层还可能提前抛出参数异常。Python 队列超时为 `queue.Empty`，发现等待超时为 `TimeoutError`，不能与 AxonError 混为一类。

返回[接口总览](../api.md)。
