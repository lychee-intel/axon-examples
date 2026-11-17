# Dart 与 Flutter API 手册

适用于 ABI 0.10.x 的 `axon_dart` 包，导入 `package:axon_dart/axon.dart`。原生调用大多同步执行，数据结果通过 Dart Stream 异步交付。设备查询和配置返回时不代表已经收到样本。公共类型与约束见[数据约定](types.md)。

## 创建与配置

```dart
Axon({DynamicLibrary? library, AxonCreateOptions? options})
AxonCreateOptions({int providerFlags = 3,
  LycheeProviderOptions lychee = const LycheeProviderOptions()})
LycheeProviderOptions({int transportFlags = 15, int tcpPort = 31200,
  int udpPort = 31300, int multicastPort = 31400, String? multicastGroup})
```

以上为签名说明。library 可注入已加载的动态库，省略使用包的加载器。providerFlags 按 `AxonCreateProviderFlags.lychee`（1）、simulator（2）组合；transportFlags 按 `AxonLycheeTransportFlags.tcp/udp/multicast/mdns`（1/2/4/8）组合。null multicastGroup 采用协议默认值。

`void start()` 启动；`void shutdown()` 永久关闭运行时；`void dispose()` 释放。shutdown 后需要重新创建 Axon 才能再次启动。静态 `Axon.logInit(LogLevel level, {String? logPath})` 设置进程级日志，null 路径使用 stderr。

加载失败可能抛动态库加载异常，创建失败抛 StateError，原生操作失败抛 AxonException；错误参数可能提前抛 ArgumentError 或 RangeError。不要把所有错误都当成等待数据超时。

## 查询设备与创建 Session

| 接口 | 返回值 | 说明 |
| --- | --- | --- |
| `devices()` | `List<DeviceInfo>` | 当前设备快照，可为空 |
| `deviceStreams(String serial)` | `List<DeviceStreamInfo>` | 流描述，含采样模式、采样率和通道数 |
| `deviceStreamChannels(String serial, String streamId)` | `List<DeviceStreamChannelInfo>` | 通道顺序、名称、单位和 gain |
| `deviceStreamMetadata(String serial, String streamId)` | `Map<String,String>` | 复制的扩展信息 |
| `newSession(String serial)` | `AxonSession` | 只绑定设备，不自动订阅 |
| `session.streams` | `List<DeviceStreamInfo>` | 查询该设备流描述 |

查询 serial 使用设备实际返回值；设备断开时，后续查询或创建 Session 可能报 notFound/invalidState。查询到流之后，再把它的 id 传入订阅或管线。

## 模拟器

```dart
AxonSimulator startSimulator({required DeviceModel model,
  required String serial, CustomSimulatorOptions? customOptions})
```

Axon 已启动时调用。DeviceModel 包含 lycheePfc、lycheePfcNirs、lycheePfcSingleChannel、custom；仅 custom 必须且允许传 `CustomSimulatorOptions(eegChannels: ..., nirsEnabled: ...)`。eegChannels 可为 1–64 或 null，nirsEnabled 默认 false，至少启用一类信号。Custom EEG 为 250 Hz，双通道 NIRS 为 20 Hz。

模拟器返回 id、serial、model；`stop()` 幂等。Lychee serial 为六位十六进制，Custom serial 为 1–64 个 ASCII 字母、数字、点、下划线或短横线。不要让 serial 与其他设备重复。

## 订阅与数据 Stream

```dart
AxonSubscription subscribeRaw(String streamId,
  {int deliveryMask = axonDeliveryAll})
AxonProcessingPipeline createPipeline(String streamId)
AxonSubscription pipeline.subscribe({int deliveryMask = axonDeliveryAll})
```

前两个方法属于 AxonSession。deliveryMask 控制投递消息类别；默认全部。原始订阅的 sourceKind 为 raw，管线订阅为 processed。管线只接受均匀采样流。

| AxonSubscription 属性 | 类型 | 含义 |
| --- | --- | --- |
| `signal` | `Stream<SampleBlock>` | 来源的时域样本，名字 signal 不代表频段分析 |
| `events` | `Stream<AxonEvent>` | 实验事件 |
| `spectrum` | `Stream<SpectrumBlock>` | 频谱 |
| `bandPower` | `Stream<SignalBlock>` | 频段功率 |
| `cognitive` | `Stream<CognitiveMetrics>` | 认知指标 |
| `quality` | `Stream<TimeQualityMetrics>` | 时间域质量 |

用 `.listen()` 接收数据，保留返回的 Dart `StreamSubscription` 并 await cancel；它与 SDK 的 AxonSubscription 是不同对象。取消 listener 只结束这个 Dart 消费者，SDK 对象仍需 dispose。

每个 Dart listener 独立缓冲；样本和各分析/事件队列最多保留 64 项，暂停后超过容量丢弃最旧项。AxonSubscription 的 `dataDroppedCount`、`eventDroppedCount`、`spectrumDroppedCount`、`signalDroppedCount`、`cognitiveDroppedCount`、`qualityDroppedCount` 汇总对应消费者丢弃情况。

`pollEvents({int maxEvents = 64})` 返回诊断列表，区别于 events 注释流。SampleBlock 的 startTimestamp、sampleOffsetsUs 使用微秒，data 为按帧交错的样本；详见[数据布局](types.md#sampleblock-与事件)。

## 滤波与分析配置

管线提供 `addFilter(AxonFilterStage stage)`、`replaceFilters(Iterable<AxonFilterStage> stages)`、`clearFilters()`，均返回 void。

```dart
const AxonFilterStage({required FilterType filterType,
  required FilterKind kind, required double cutoffHz,
  double cutoff2Hz = 0, required int order, double q = 0})
```

FilterType 为 fir/iir，FilterKind 为 lowPass/highPass/bandPass/bandStop/notch。order 必须显式给出。带通/带阻使用 cutoffHz 与 cutoff2Hz；频率相对于所选流 Nyquist 校验。

处理后 AxonSubscription 的分析配置均返回 void：

| 方法与默认参数 | 输出 |
| --- | --- |
| `configureSpectrum({fftSize=1024, hop})` | spectrum |
| `configureSignal({fftSize=1024, hop, selectedChannel=0})` | bandPower |
| `configureCognitive({alpha=0.15, rangeMin=0, rangeMax=3, attentionMedianWindow=3, fftSize=256, hop, selectedChannel=0})` | cognitive |
| `configureTimeQuality({minSamples=2, flatlineDelta=1e-6, clipLow, clipHigh, transientDelta})` | quality |

hop 为 null 时使用半窗口。clipLow 与 clipHigh 必须同时给出或同时为 null。FFT、通道索引和信号种类约束见[分析参数](types.md#分析参数与结果)。`clearSpectrum()`、`clearSignal()`、`clearCognitive()`、`clearTimeQuality()` 分别关闭对应分析。配置失败保留旧配置，成功替换重置历史。

## 录制与完整采集示例

`raw.startRecording(String path, {Map<String,Object?>? metadata})` 和管线的同名方法返回 RecordingHandle。处理后订阅不能直接作为录制来源，改用其管线。

RecordingHandle 提供 `state`、`pushEvent({required int onset, int duration = 0, required String eventType, String description = ''})`、`RecordingResult finish()`、`abort()`、`dispose()`。onset 为绝对 epoch 微秒；duration 为非负微秒时长。finish 返回 path、Duration duration、totalSamples、numChannels、sampleRateHz、startTimestamp、endTimestamp 和 nullable lastSampleTimestamp。

以下是可放入 Dart 入口文件的完整示例，使用 Custom 模拟器读取三块数据并保存。`sample.axf` 为输出文件，原生库须已部署。

```dart
import 'package:axon_dart/axon.dart';

Future<void> main() async {
  final axon = Axon(options: const AxonCreateOptions(
    providerFlags: AxonCreateProviderFlags.simulator,
    lychee: LycheeProviderOptions(transportFlags: 0),
  ));
  try {
    axon.start();
    final simulator = axon.startSimulator(
      model: DeviceModel.custom,
      serial: 'dart-demo',
      customOptions: CustomSimulatorOptions(eegChannels: 2),
    );
    try {
      final session = axon.newSession(simulator.serial);
      try {
        final raw = session.subscribeRaw('eeg');
        try {
          final recording = raw.startRecording('sample.axf');
          try {
            await for (final block in raw.signal
                .timeout(const Duration(seconds: 10)).take(3)) {
              print('${block.startTimestamp}: ${block.numSamples} frames');
            }
            print(recording.finish().path);
          } finally {
            recording.dispose();
          }
        } finally {
          raw.dispose();
        }
      } finally {
        session.dispose();
      }
    } finally {
      simulator.stop();
    }
  } finally {
    axon.dispose();
  }
}
```

timeout 是 Dart Stream 的等待策略，不会自动保存录制。发生异常时 finally 仍清理对象，未 finish 的采集录制会被取消。

## AXF 读取、写入与导出

`AxfReader.open(String path, {DynamicLibrary? library})` 返回独立 reader，无需 Axon。它提供：

| 接口 | 返回值 |
| --- | --- |
| `info()` / `readEvents()` / `verify()` | AxfInfo / List<AxonEvent> / bool |
| `readBlock(int timestamp)` | 精确起始时间匹配的首块 |
| `readBlockByIndex(int index)` | 零起始逻辑块，返回 AxfBlock |
| `readRange(int start, int end)` | List<AxfBlock>，按起始时间筛选完整块 |
| `readBlocks(int start, int end, {int batchSize=64})` | Iterable<AxfBlock>，有界批次，batchSize > 0 |
| `close()` / `dispose()` | 幂等释放 |

范围为 `[start,end)`，不裁剪块内样本；遍历时保持 reader 有效并串行使用。

`AxfWriter.create(String path, List<AxfStreamDefinition> streams, {AxfWriterOptions? options, DynamicLibrary? library})` 创建/截断文件。AxfStreamDefinition 要求 id、name、sampleRateHz、channels；kind 默认 0，samplingMode 默认 0，metadata 为 `Map<String,String>?`。通道使用 AxfChannelDefinition，要求 name、label、unit。

writer 提供 `writeBlock`、`pushEvent`、`flush`、`finish`、`close` / `dispose`。writeBlock 的位置参数为 streamId、startTimestamp、numFrames、samples，可通过命名参数 sampleOffsetsUs 传不规则帧时间。样本数必须等于帧数×通道数；文件 id 为 uint16。options 默认 zstd 压缩和 f32 样本；显式 finish 才完成文件，close 不自动保存或删除。

Axon 提供同步导出：

- `exportAxfStream(String axfPath, int streamId, AxfExportFormat format, String outputPath)`：edf/bdf/csv 单流导出，注意 format 位于 outputPath 前。
- `exportAxfXdf(String axfPath, String outputPath)`：整份录制，输出文件须不存在。
- `exportAxfGbt47127(String axfPath, String datasetDirectory, {void Function(AxfExportProgress)? onProgress})`：同步进度回调不可重入 SDK。

## LSL 与健康通知

原始订阅与管线提供 `startLsl({LslPublishOptions? options}) -> LslPublisher`。`LslPublishOptions(name: ..., queueCapacity: 64)` 的名称可省略，队列容量为正。publisher 提供 status、stop()、dispose()；status 包含发布状态、名称、sourceId、logicalId、publishedFrames、rejectedBlocks、error。发布失败不会因为 stop 变回成功。

`axon.healthSnapshot() -> HealthSnapshot` 返回复制的不可变快照；`axon.transportStatus -> Stream<TransportStatusEvent>` 提供变化。先 listen，再 start/查询初始快照，通知不补发历史。Dart listener 的 cancel 需要 await，最后 dispose Axon。snapshot 含 health、providers；provider 含 providerId、health、categories，类别含 transport、health、detail。

LSL 部署及支持范围见[接入指南](../getting-started.md)，共享错误码见[公共约定](types.md#错误码)。返回[接口总览](../api.md)。
