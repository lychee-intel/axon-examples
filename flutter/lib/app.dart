import 'dart:async';
import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';

import 'spectrum_canvas.dart';
import 'signal_canvas.dart';
import 'waveform.dart';
import 'filter_config.dart';
import 'device_stream_config.dart';
import 'attention_score.dart';

/// 数据源：协议模拟器 / EEG 分数模拟器 / 力之真实数据。
enum _DataSource { simulator, eegSimulator, lychee }

/// 应用根：MaterialApp + 主屏幕。
class AxonDemoApp extends StatelessWidget {
  const AxonDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Axon EEG Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const AxonDemoScreen(),
    );
  }
}

/// 主屏幕：启停按钮、通道选择和实时分析画布。
class AxonDemoScreen extends StatefulWidget {
  const AxonDemoScreen({super.key});

  @override
  State<AxonDemoScreen> createState() => _AxonDemoScreenState();
}

class _AxonDemoScreenState extends State<AxonDemoScreen> {
  late final Axon _axon;
  AxonSession? _deviceSession;
  AxonProcessingPipeline? _pipeline;
  AxonSubscription? _session;
  AxonProcessingPipeline? _attentionPipeline;
  AxonSubscription? _attentionSession;
  Timer? _attentionTimer;
  final _attention = AttentionScoreHistory();
  AxonSimulator? _simulator;
  StreamSubscription<SampleBlock>? _dataSub;
  bool _running = false;
  _DataSource _dataSource = _DataSource.simulator;
  int _numChannels = 3;
  List<String> _channelLabels = List.generate(3, (i) => 'CH${i + 1}');
  double _sampleRateHz = 250;
  int _channel = 0;
  int _viewMode = 0; // 0=波形 1=频谱 2=信号 3=注意力分数
  final List<double> _recorded = [];

  /// Dart 侧维护的滤波器链（每次 start 时重建 native pipeline）。
  final List<FilterEntry> _filters = [FilterEntry()]; // 默认带一个 40Hz 低通

  @override
  void initState() {
    super.initState();
    _axon = Axon();
  }

  void _start() {
    _attention.begin();
    try {
      final serial = switch (_dataSource) {
        _DataSource.simulator => () {
          _axon.start();
          final simulator = _axon.startSimulator(
            model: DeviceModel.lycheeBci100,
            serial: '0A1B2C',
          );
          _simulator = simulator;
          return simulator.serial;
        }(),
        _DataSource.eegSimulator => () {
          _axon.start();
          final simulator = _axon.startSimulator(
            model: DeviceModel.custom,
            serial: 'attention-preview',
            customOptions: CustomSimulatorOptions(eegChannels: 3),
          );
          _simulator = simulator;
          return simulator.serial;
        }(),
        _DataSource.lychee => () {
          _axon.start();
          final devices = _axon.devices();
          if (devices.isEmpty) throw StateError('尚未发现已连接设备');
          return devices.first.serial;
        }(),
      };
      final stream = selectDemoStream(_axon.deviceStreams(serial));
      final deviceSession = _axon.newSession(serial);
      _deviceSession = deviceSession;
      final pipeline = deviceSession.createPipeline(stream.id);
      _pipeline = pipeline;
      _numChannels = stream.numChannels;
      _sampleRateHz = stream.sampleRateHz;
      _channelLabels = _axon
          .deviceStreamChannels(serial, stream.id)
          .map(
            (channel) => channel.label.isEmpty ? channel.name : channel.label,
          )
          .toList(growable: false);
      _channel = 0;
      _recorded.clear();
      for (final filter in _filters) {
        pipeline.addFilter(filter.toStage());
      }
      final session = pipeline.subscribe();
      _session = session;
      // 默认频谱配置：fft 1024、hop 512（50% 重叠）、Hann、symmetric、Amplitude 刻度。
      session.configureSpectrum(fftSize: 1024, hop: 512);
      // 默认信号分析配置：与频谱同参数，selectedChannel 跟随当前通道。
      session.configureSignal(
        fftSize: 1024,
        hop: 512,
        selectedChannel: _channel,
      );
      // 认知指标（Focus/Calm/SQI），供 SignalCanvas 下半部分显示。
      session.configureCognitive();
      session.events.listen((e) {
        debugPrint('axon event: ${e.eventType} @ ${e.onset}');
      });
      _dataSub = session.signal.listen((b) => _recorded.addAll(b.data));
      _startAttention(deviceSession, stream.id);
      switch (_dataSource) {
        case _DataSource.lychee:
          setState(() {
            _running = true;
            _channel = 0;
          });
        case _DataSource.simulator:
        case _DataSource.eegSimulator:
          setState(() => _running = true);
      }
    } catch (e) {
      _stop();
      _showMessage('启动失败：$e');
    }
  }

  void _startAttention(AxonSession deviceSession, String streamId) {
    try {
      // The score uses every EEG channel on its own unfiltered branch.
      final pipeline = deviceSession.createPipeline(streamId);
      _attentionPipeline = pipeline;
      final subscription = pipeline.subscribe();
      _attentionSession = subscription;
      subscription.configureAttentionScore();
      _attentionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        try {
          for (final event in subscription.pollAttentionScores()) {
            _attention.add(event);
          }
        } catch (error) {
          _closeAttention();
          _attention.fail('$error');
        }
      });
    } catch (error) {
      _closeAttention();
      _attention.fail('$error');
    }
  }

  void _closeAttention() {
    _attentionTimer?.cancel();
    _attentionTimer = null;
    _attentionSession?.dispose();
    _attentionSession = null;
    _attentionPipeline?.dispose();
    _attentionPipeline = null;
  }

  void _stop() {
    _closeAttention();
    _attention.stop();
    _dataSub?.cancel();
    _dataSub = null;
    _session?.dispose();
    _session = null;
    _pipeline?.dispose();
    _pipeline = null;
    _deviceSession?.dispose();
    _deviceSession = null;
    _simulator?.stop();
    _simulator = null;
    setState(() => _running = false);
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openFilterSheet() {
    showFilterSheet(
      context,
      filters: _filters,
      sampleRateHz: _sampleRateHz,
      onApply: (updated) {
        setState(
          () => _filters
            ..clear()
            ..addAll(updated),
        );
      },
    );
  }

  @override
  void dispose() {
    _closeAttention();
    _attention.dispose();
    _dataSub?.cancel();
    _session?.dispose();
    _pipeline?.dispose();
    _deviceSession?.dispose();
    _simulator?.stop();
    _axon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Axon EEG Demo'),
        actions: [
          IconButton(
            onPressed: _openFilterSheet,
            icon: const Icon(Icons.tune),
            tooltip: 'Filters',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _running ? _stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
                SegmentedButton<_DataSource>(
                  segments: const [
                    ButtonSegment(
                      value: _DataSource.simulator,
                      label: Text('Lychee BCI100 模拟器'),
                      icon: Icon(Icons.memory),
                    ),
                    ButtonSegment(
                      value: _DataSource.eegSimulator,
                      label: Text('EEG 分数模拟器'),
                      icon: Icon(Icons.science_outlined),
                    ),
                    ButtonSegment(
                      value: _DataSource.lychee,
                      label: Text('力之真实数据'),
                      icon: Icon(Icons.sensors),
                    ),
                  ],
                  selected: {_dataSource},
                  onSelectionChanged: _running
                      ? null
                      : (sel) async {
                          final src = sel.first;
                          _attention.reset();
                          setState(() {
                            _dataSource = src;
                            _recorded.clear();
                            _numChannels = 3;
                            _channel = 0;
                            _sampleRateHz = 250;
                          });
                        },
                ),
                if (_running)
                  DropdownButton<int>(
                    value: _channel,
                    items: _channelLabels
                        .asMap()
                        .entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _channel = v);
                      // 信号分析跟随当前通道
                      _session?.configureSignal(
                        fftSize: 1024,
                        hop: 512,
                        selectedChannel: v,
                      );
                    },
                  ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('波形'),
                      icon: Icon(Icons.show_chart),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('频谱'),
                      icon: Icon(Icons.graphic_eq),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text('信号'),
                      icon: Icon(Icons.insights),
                    ),
                    ButtonSegment(
                      value: 3,
                      label: Text('注意力分数'),
                      icon: Icon(Icons.psychology),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (sel) =>
                      setState(() => _viewMode = sel.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _viewMode == 3
                      ? AttentionScoreView(history: _attention)
                      : _viewMode == 1
                      ? SpectrumCanvas(
                          key: ObjectKey(_session),
                          stream: _session?.spectrum ?? const Stream.empty(),
                          channel: _channel,
                        )
                      : _viewMode == 2
                      ? SignalCanvas(
                          key: ObjectKey(_session),
                          stream: _session?.bandPower ?? const Stream.empty(),
                          cognitiveStream: _session?.cognitive,
                        )
                      : WaveformCanvas(
                          key: ObjectKey(_session),
                          stream: _session?.signal ?? const Stream.empty(),
                          numChannels: _numChannels,
                          channelLabels: _channelLabels,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
