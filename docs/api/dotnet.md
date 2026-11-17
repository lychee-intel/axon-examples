# C# 与 .NET API 手册

适用于 ABI 0.10.x 的 `Axon` 包。主要命名空间为 `Axon.Devices`、`Axon.Sessions`、`Axon.Processing`、`Axon.Delivery`、`Axon.Recordings`、`Axon.Streaming`、`Axon.Configuration` 和 `Axon.Diagnostics`。公共数据与状态见[类型约定](types.md)。

## 创建配置与生命周期

`new Axon.Axon(AxonCreateOptions? options = null)` 创建未启动实例。`Start()` 启动，`Shutdown()` 永久关闭，`Dispose()` 释放；建议使用 using 管理对象，保存录制必须发生在 Dispose 前。

| 配置属性 | 默认值 | 说明 |
| --- | --- | --- |
| `AxonCreateOptions.Providers` | Lychee \| Simulator | AxonProviderFlags，可按位组合 |
| `AxonCreateOptions.Lychee` | new LycheeProviderOptions() | Lychee 专属配置 |
| `LycheeProviderOptions.Transports` | Tcp \| Udp \| Multicast \| Mdns | LycheeTransportFlags |
| `TcpPort` / `UdpPort` / `MulticastPort` | 31200 / 31300 / 31400 | ushort |
| `MulticastGroup` | null | 协议默认组播地址 |

`Axon.Axon.LogInit(LogLevel level, string? logPath = null)` 配置进程日志；null 路径使用 stderr。原生库加载与 ABI 不匹配在初始化时报错；原生操作错误以 AxonException 报告，参数与已释放对象通常分别抛 ArgumentException 派生类型和 ObjectDisposedException。

## 设备、模拟器与 Session

| 方法 | 返回类型 | 行为 |
| --- | --- | --- |
| `axon.DeviceCount()` | int | 当前数量 |
| `axon.Devices()` | IReadOnlyList<Device> | 当前设备列表，可能为空 |
| `axon.WaitForDeviceAsync(TimeSpan? timeout=null, CancellationToken cancellationToken=default)` | Task<Device> | 异步等待，支持超时和取消 |
| `device.Info` | DeviceInfo | 身份描述 |
| `device.Streams` | IReadOnlyList<DeviceStreamInfo> | 实时流描述 |
| `device.StreamChannels(string streamId)` | IReadOnlyList<DeviceStreamChannelInfo> | 通道布局 |
| `device.StreamMetadata(string streamId)` | DeviceStreamMetadata | 扩展描述 |
| `device.OpenSession()` | Session | 创建指定设备会话 |
| `session.GetStream(string streamId)` | DeviceStream | 按已知 id 选择流，未知流报错 |

Device 是身份视图，不持有连接；断线后查询可能失败。Session.Streams 为其流描述快照，不能把持有 Device/Session 当作设备永远在线的保证。

`axon.AddSimulator(DeviceModel model, string serial, CustomSimulatorOptions? customOptions=null) -> Simulator` 要求已 Start。DeviceModel 为 LycheeBci100、LycheeBci100E、LycheeBcs100、LycheeBch100、Custom；只有 Custom 需要 customOptions，其他型号禁止传入。Lychee 型号的固定 EEG 通道数依次为 3、3、1、32，BCI100-E 另含双通道 NIRS。

CustomSimulatorOptions 使用工厂创建：`Eeg(int channels)`、`Nirs()`、`EegAndNirs(int channels)`，EEG 为 1–64 通道、250 Hz，NIRS 双通道、20 Hz。Simulator 提供 Id、Serial、Model、Device；Stop() 幂等，Dispose() 也会停止。serial 约束见[Python 模拟器说明](python.md#模拟器)，与语言无关。

## 订阅、管线与 reader

```csharp
StreamSubscription stream.Subscribe(SubscriptionOptions? options = null)
ProcessingPipeline stream.CreatePipeline()
StreamSubscription pipeline.Subscribe(SubscriptionOptions? options = null)
void pipeline.SetFilters(IEnumerable<FilterStageConfig> stages)
```

stream 是 `session.GetStream(id)` 的结果。stream.Subscribe 创建原始订阅；pipeline.Subscribe 创建处理后订阅。SourceKind 区分 Raw/Processed。ProcessingPipeline 只支持均匀采样流，滤波链替换失败保留旧链。

FilterStageConfig 参数为 `(FilterType FilterType=Fir, FilterKind Kind=LowPass, double CutoffHz=0, double Cutoff2Hz=0, ushort Order=4, double Q=0)`。使用时明确指定有效 cutoff 和 filter kind，不把默认零频率作为可用滤波器。

StreamSubscription 提供以下独立消费者，均接受 `ReaderOptions? options = null`：

| 方法 | 返回类型 |
| --- | --- |
| `CreateDataReader()` | DeliveryReader<SampleBlock> |
| `CreateEventReader()` | DeliveryReader<AxonEvent> |
| `CreateSpectrumReader()` | DeliveryReader<SpectrumBlock> |
| `CreateSignalReader()` | DeliveryReader<SignalBlock> |
| `CreateCognitiveReader()` | DeliveryReader<CognitiveMetrics> |
| `CreateQualityReader()` | DeliveryReader<TimeQualityResult> |

reader 创建时立即注册，不是等到枚举才开始缓冲。`ReadAllAsync(CancellationToken cancellationToken=default)` 返回异步序列，每个 reader 只允许枚举一次；多个消费者分别创建 reader。取消、退出枚举或 Dispose 注销并清理该 reader，不代表关闭 SDK 订阅或它的父管线。

## 容量与丢弃策略

SubscriptionOptions.Delivery 默认 DeliveryKinds.All，控制原生投递类别；NativeQueue 是原生队列配置。ReaderOptions 控制每个托管 reader 的队列，两者分别限制不同阶段。

| 配置 | 默认值 | 限制 |
| --- | --- | --- |
| NativeQueue.MessageCapacity | 256 | 1–256 |
| NativeQueue.ByteCapacity | 16 MiB | 正数 |
| NativeQueue.ControlCapacity | 64 | 1–256 |
| NativeQueue.ControlByteCapacity | 1 MiB | 正数 |
| NativeQueue.OverflowPolicy | DropOldest | 支持 DropOldest/DropNewest，不支持 Fail |
| ReaderOptions.Capacity | 256 | 正数 |
| ReaderOptions.ByteCapacity | 16 MiB | 正数，计算复制载荷，不包含 CLR 对象开销 |
| ReaderOptions.OverflowPolicy | DropOldest | DropOldest / DropNewest / Fail |

`ReaderOptions.Latest` 的容量为 1，适用于只显示最新结果。容量和字节预算独立生效，单个 oversized 载荷也可能被丢弃或触发 Fail。通过 `reader.Stats` 检查该消费者，通过 `subscription.GetManagedDeliveryStats(DeliveryKind)` / `GetNativeDeliveryStats(DeliveryKind)` 检查分阶段计数。`ProcessingStats` 与 `PollEvents(int maxEvents=64)` 提供采集/处理统计和诊断。

## 分析选项

以下方法用于处理后订阅，参数省略时使用对应默认配置：

| 方法 | options 类型与默认属性 |
| --- | --- |
| `ConfigureSpectrum(SpectrumOptions? options=null)` | FftSize=1024，Hop=null（半窗口） |
| `ConfigureSignal(SignalOptions? options=null)` | FftSize=1024，Hop=null，SelectedChannel=0 |
| `ConfigureCognitive(CognitiveOptions? options=null)` | Alpha=0.15，RangeMin=0，RangeMax=3，AttentionMedianWindow=3，FftSize=256，Hop=128，SelectedChannel=0 |
| `ConfigureQuality(QualityOptions? options=null)` | MinSamples=2，FlatlineDelta=1e-6，ClipLow/ClipHigh/TransientDelta=null |

对应 ClearSpectrum、ClearSignal、ClearCognitive、ClearQuality 关闭分析。注意：修改 CognitiveOptions.FftSize 而不指定 Hop 时，其默认 Hop 仍为 128；需要自动半窗口可显式设置 Hop=null。

配置与 FFT 约束见[公共分析约定](types.md#分析参数与结果)。创建分析 reader 与启用分析是两步：仅 CreateSpectrumReader 不会自动 ConfigureSpectrum。

## 完整模拟采集与录制

以下代码可作为控制台应用的顶层入口，在已安装包和部署原生库后读取三个 block 并保存文件。取消令牌限制等待时间，超时抛 OperationCanceledException，未 finish 的录制在清理时取消。

```csharp
using Axon.Devices;

using var axon = new Axon.Axon();
axon.Start();
using var simulator = axon.AddSimulator(
    DeviceModel.LycheeBci100, "010203");
using var session = simulator.Device.OpenSession();
using var raw = session.GetStream("eeg").Subscribe();
using var reader = raw.CreateDataReader();
using var recording = raw.StartRecording("sample.axf");
using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
var count = 0;
await foreach (var block in reader.ReadAllAsync(timeout.Token))
{
    Console.WriteLine($"{block.StartTimestampUs}: {block.FrameCount} frames");
    if (++count == 3) break;
}
Console.WriteLine(recording.Finish().Path);
```

SampleBlock 提供 StartTimestampUs、SampleRateHz、ChannelCount、FrameCount、Samples、FrameOffsetsUs、StreamId、Sequence、SequenceSaturated。Samples 为 ReadOnlyMemory<float>；`GetSample(frameIndex,channelIndex)` 按帧交错访问，`GetFrameTimestampUs(frameIndex)` 读取对应帧绝对时间。

## Recording

原始订阅和 ProcessingPipeline 提供 `StartRecording(string path, RecordingMetadata? metadata=null) -> Recording`。metadata 类型位于 Axon.Recordings.Metadata；不能从处理后订阅直接录制。

| 接口 | 行为 |
| --- | --- |
| `State` | RecordingState：Active、FinalizationFailed、Saved、Cancelled |
| `AddEvent(long onsetUs, long durationUs, string eventType, string description="")` | 写入实验事件，时间单位微秒 |
| `Finish()` | 返回 RecordingResult；保存须在来源关闭之前 |
| `Abort()` | 取消未完成输出，不删除 Saved |
| `Dispose()` | 释放；未完成录制取消 |

RecordingResult 包含 Path、DurationUs、TotalSamples、ChannelCount、SampleRateHz、StartTimestampUs、EndTimestampUs、nullable LastSampleTimestampUs，最后实际样本时间与时长边界不同。处理后显示 reader/订阅结束不影响独立的 pipeline 录制。

## AXF 文件读写与导出

`AxfReader.Open(string path)` 返回可 using 的 reader；Info 属性返回文件描述，ReadEvents() 返回事件，Verify() 返回 bool。`ReadBlock(long timestamp)` 精确匹配首块，`ReadBlockByIndex(nuint index)` 使用零起始逻辑索引，`ReadBlocks(long startTimestampUs,long endTimestampUs,int batchSize=64)` 分批枚举起始时间位于 `[start,end)` 的完整块，不裁剪样本。枚举期间保持 reader 有效。

`AxfWriter.Create(string path,IReadOnlyList<AxfStreamDefinition> streams,AxfWriterOptions? options=null)` 创建/截断文件。AxfStreamDefinition 构造参数为 Id、Name、Kind、SampleRateHz、Channels，SamplingMode 默认 Uniform，Metadata/VendorKind 可省略。AxfChannelDefinition 要求 Name、Label、Unit，ChannelType 默认 Eeg，Gain 默认 1。

writer 的 `WriteBlock(ushort streamId,long startTimestampUs,int frameCount,ReadOnlySpan<float> samples,ReadOnlySpan<ulong> frameOffsetsUs=default)` 写样本。不规则流每帧需一个偏移；samples 长度为 frameCount×通道数。PushEvent 写事件，Flush 刷出，Finish 完成索引/Footer，Dispose 不会替代 Finish，也不删除文件。AxfWriterOptions 默认 Zstd/F32；可设置 StartTimestampUs、DeviceInfo、字符串 Metadata 和 PhysicalRange。

AxfExporter 为静态入口，无需 Axon：

- `ExportStream(string axfPath,ushort streamId,ExportFormat format,string outputPath)`：Edf/Bdf/Csv 单流导出。
- `ExportXdf(string axfPath,string outputPath)`：整份录制，目标文件须不存在，无需 liblsl。
- `ExportGbt47127(string axfPath,string datasetDirectory,Action<AxonExportProgress>? progress=null)`：同步导出，progress 回调不重入 SDK。

## LSL 与健康状态

原始订阅与 ProcessingPipeline 提供 `StartLsl(LslPublishOptions? options=null) -> LslPublisher`。options 的 Name 默认 null，QueueCapacity 默认 64 且必须为正。publisher.Status 返回 State、Name、LogicalId、SourceId、PublishedFrames、RejectedBlocks、Error；Stop 幂等，Dispose 释放。来源关闭会停止发布，Failed 原因保留。详见[部署说明](../getting-started.md#准备语言包与运行库)。

`axon.GetHealthSnapshot()` 返回不可变 HealthSnapshot；`axon.TransportStatusChanged` 事件提供变化。先注册事件，再启动或读取初始快照，通知不回放。handler 在托管 worker 上执行，允许查询和释放，handler 异常隔离；UI 更新仍需 Dispatcher 等框架机制。

Health 为 Healthy/Degraded/Failed，类别为 Network/Usb/Serial/Ble，类别缺席表示未报告；状态变化不等价于设备断线。快照含 Health、Providers，每个 provider 含 ProviderId、Health、Categories；类别含 Transport、Health、Detail。快照独立拥有复制数据。

## 离线 EEG 窗口与频谱

`Axon.Processing.OfflineEegAnalyzer` 无需创建 Axon 或 Session。
先检查 `Available` 和 `SpectrumAvailable`，旧版 ABI 0.10 可能不含可选接口。

```csharp
using Axon.Processing;

var analyzer = new OfflineEegAnalyzer();
if (analyzer.Available && analyzer.SpectrumAvailable)
{
    var samples = Enumerable.Range(0, 1024)
        .Select(i => (float)Math.Sin(2 * Math.PI * 10 * i / 256)).ToArray();
    var window = analyzer.Analyze(samples, 256,
        new QualityOptions { ClipLow = -2, ClipHigh = 2 }, includeSpectrum: true);
    if (window.Spectrum is { } psd)
    {
        var alpha = analyzer.SpectrumBand(psd.ToArray(), 1024, 256, 8, 13);
        Console.WriteLine($"Alpha: {alpha.Power}, peak: {alpha.PeakHz} Hz");
    }
}
```

输入为单通道 4–65536 点、长度为 2 的幂。结果不可变，Status 区分 Usable、
Insufficient、NonFinite、Flatline、NumericalFailure；拒绝窗口的 Spectrum 为 null。
Powers 按 SignalBand 顺序，单位为输入单位平方，不可用为 null，有效零值为 0。
PSD 是含 DC/Nyquist 的单边 symmetric-Hann 密度，单位为输入单位平方/Hz。
多窗口先平均有效 PSD，再用 SpectrumBand 积分/找峰；峰值相同取最低频率，
零功率无峰，超出 Nyquist 的完整频带不可用。上界通常不含，仅等于 Nyquist 时包含。

返回[接口总览](../api.md)。
