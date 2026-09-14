import 'dart:async';
import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';

import 'spectrum_canvas.dart';
import 'signal_canvas.dart';
import 'waveform.dart';
import 'filter_config.dart';

/// 数据源：模拟器 / 力之真实数据（三路监听）/ EDF 文件。
enum _DataSource { simulator, lychee }

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

/// 主屏幕：启停按钮、通道选择、实时波形画布、EDF 保存/加载。
class AxonDemoScreen extends StatefulWidget {
  const AxonDemoScreen({super.key});

  @override
  State<AxonDemoScreen> createState() => _AxonDemoScreenState();
}

class _AxonDemoScreenState extends State<AxonDemoScreen> {
  late final Axon _axon;
  AxonSession? _session;
  StreamSubscription<SampleBlock>? _dataSub;
  bool _running = false;
  _DataSource _dataSource = _DataSource.simulator;
  int _numChannels = 19;
  double _sampleRateHz = 250;
  int _channel = 0;
  int _viewMode = 0; // 0=波形 1=频谱 2=信号
  final List<double> _recorded = [];
  /// Dart 侧维护的滤波器链（每次 start 时重建 native pipeline）。
  final List<FilterEntry> _filters = [FilterEntry()]; // 默认带一个 40Hz 低通

  @override
  void initState() {
    super.initState();
    _axon = Axon();
  }

  void _start() {
    try {
      final session = switch (_dataSource) {
        _DataSource.simulator => () {
            const serial = 'simulator';
            _axon.start();
            _axon.addSimulator(serial,
                channels: _numChannels, sampleRateHz: _sampleRateHz);
            return _axon.newSession(serial);
          }(),
        _DataSource.lychee => () {
            _axon.start();
            final devices = _axon.devices();
            if (devices.isEmpty) throw StateError('尚未发现已连接设备');
            return _axon.newSession(devices.first.serial);
          }(),
      };
      _session = session;
      for (final filter in _filters) {
        session.addFilter(filter.toStage(_sampleRateHz));
      }
      // 默认频谱配置：fft 1024、hop 512（50% 重叠）、Hann、symmetric、Amplitude 刻度。
      session.configureSpectrum(fftSize: 1024, hop: 512);
      // 默认信号分析配置：与频谱同参数，selectedChannel 跟随当前通道。
      session.configureSignal(fftSize: 1024, hop: 512, selectedChannel: _channel);
      // 认知指标（Focus/Calm/SQI），供 SignalCanvas 下半部分显示。
      session.configureCognitive();
      session.events.listen((e) {
        debugPrint('axon event: ${e.eventType} @ ${e.onset}');
      });
      _dataSub = session.signal.listen((b) => _recorded.addAll(b.data));
      switch (_dataSource) {
        case _DataSource.lychee:
          setState(() {
            _running = true;
            _numChannels = 3;
            _sampleRateHz = 250;
            _channel = 0;
          });
        case _DataSource.simulator:
          setState(() => _running = true);
      }
    } catch (e) {
      _showMessage('启动失败：$e');
    }
  }

  void _stop() {
    _dataSub?.cancel();
    _dataSub = null;
    _session?.dispose();
    _session = null;
    if (_dataSource == _DataSource.lychee) _axon.stop();
    setState(() => _running = false);
  }


  void _showMessage(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openFilterSheet() {
    showFilterSheet(
      context,
      filters: _filters,
      sampleRateHz: _sampleRateHz,
      onApply: (updated) {
        setState(() => _filters
          ..clear()
          ..addAll(updated));
      },
    );
  }

  /// 通道标签：力之设备使用 10-20 frontopolar 命名，其他使用编号。
  String _channelLabel(int c) {
    if (_dataSource == _DataSource.lychee) {
      const names = ['Fp1', 'Fpz', 'Fp2'];
      return c < names.length ? names[c] : 'Ch${c + 1}';
    }
    return 'Ch${c + 1}';
  }

  List<String> get _channelLabels =>
      List.generate(_numChannels, _channelLabel);

  @override
  void dispose() {
    _dataSub?.cancel();
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
                      label: Text('模拟器'),
                      icon: Icon(Icons.memory),
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
                          setState(() {
                              _dataSource = src;
                              _recorded.clear();
                              _numChannels = src == _DataSource.simulator ? 19 : 3;
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
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _channel = v);
                      // 信号分析跟随当前通道
                      _session?.configureSignal(
                        fftSize: 1024, hop: 512, selectedChannel: v,
                      );
                    },
                  ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('波形'), icon: Icon(Icons.show_chart)),
                    ButtonSegment(value: 1, label: Text('频谱'), icon: Icon(Icons.graphic_eq)),
                    ButtonSegment(value: 2, label: Text('信号'), icon: Icon(Icons.insights)),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (sel) => setState(() => _viewMode = sel.first),
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
                  child: _viewMode == 1
                      ? SpectrumCanvas(stream: _session?.spectrum ?? const Stream.empty(), channel: _channel)
                      : _viewMode == 2
                          ? SignalCanvas(
                              stream: _session?.bandPower ?? const Stream.empty(),
                              cognitiveStream: _session?.cognitive,
                            )
                          : WaveformCanvas(
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
