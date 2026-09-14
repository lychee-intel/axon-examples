import 'dart:async';

import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';

/// 7 频段颜色（与 axon-debugger BandPowerCanvas 一致）。
const _bandColors = [
  Color(0xFF4285F4), // Delta  蓝
  Color(0xFF34A853), // Theta  绿
  Color(0xFFFBBC05), // Alpha  黄
  Color(0xFFEA4335), // Beta   红
  Color(0xFF9C27B0), // LowerGamma 紫
  Color(0xFF00BCD4), // HigherGamma 青
  Color(0xFFFF9800), // SMR    橙
];

/// 3 认知指标颜色。
const _metricColors = [
  Color(0xFFFFEB3B), // Focus 黄
  Color(0xFF4CAF50), // Calm  绿
  Color(0xFF00BCD4), // SQI   青
];

const _metricLabels = ['Focus', 'Calm', 'SQI'];

/// 实时信号分析画布：订阅 [stream] 的 SignalBlock，
/// 上半部分画 7 频段功率柱状图，下半部分显示 3 个认知指标。
/// 认知指标来自独立的 [cognitiveStream]（CognitiveMetrics）。
class SignalCanvas extends StatefulWidget {
  const SignalCanvas({
    super.key,
    required this.stream,
    this.cognitiveStream,
  });

  final Stream<SignalBlock> stream;
  final Stream<CognitiveMetrics>? cognitiveStream;

  @override
  State<SignalCanvas> createState() => _SignalCanvasState();
}

class _SignalCanvasState extends State<SignalCanvas> {
  StreamSubscription<SignalBlock>? _sub;
  StreamSubscription<CognitiveMetrics>? _cogSub;
  SignalBlock? _last;
  CognitiveMetrics? _lastMetrics;
  double _maxPower = 1.0;
  static const _maxFps = 30;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
  bool _repaintScheduled = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen(_onBlock);
    _cogSub = widget.cognitiveStream?.listen((m) => _lastMetrics = m);
  }

  void _onBlock(SignalBlock block) {
    _last = block;
    var max = 0.0;
    for (var i = 0; i < 7; i++) {
      if (block.powers[i] > max) max = block.powers[i];
    }
    _maxPower = max.isFinite && max > 0 ? max : 1.0;

    if (!mounted || _repaintScheduled) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastPaint).inMicroseconds;
    const minInterval = 1000000 ~/ _maxFps;
    if (elapsed >= minInterval) {
      _lastPaint = now;
      setState(() {});
    } else if (!_repaintScheduled) {
      _repaintScheduled = true;
      final delay = Duration(microseconds: minInterval - elapsed);
      Future.delayed(delay, () {
        if (mounted) {
          _lastPaint = DateTime.now();
          _repaintScheduled = false;
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cogSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SignalPainter(
          block: _last,
          metrics: _lastMetrics,
          maxPower: _maxPower,
          textColor: scheme.onSurfaceVariant,
          bgColor: scheme.surface,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SignalPainter extends CustomPainter {
  _SignalPainter({
    required this.block,
    required this.metrics,
    required this.maxPower,
    required this.textColor,
    required this.bgColor,
  });

  final SignalBlock? block;
  final CognitiveMetrics? metrics;
  final double maxPower;
  final Color textColor;
  final Color bgColor;

  @override
  void paint(Canvas canvas, Size size) {
    final b = block;
    if (b == null) return;

    const leftPad = 8.0;
    const rightPad = 8.0;
    const topPad = 8.0;
    const bottomPad = 18.0;
    const metricsHeight = 60.0; // 注意力指标区域高度
    const gap = 12.0; // 两区域间距

    final plotW = size.width - leftPad - rightPad;
    final barsH = size.height - topPad - bottomPad - metricsHeight - gap;
    if (plotW <= 0 || barsH <= 0) return;

    // ── 上半部分：7 频段功率柱状图 ──
    final barW = plotW / 7;
    for (var i = 0; i < 7; i++) {
      final v = b.powers[i];
      final h = (v / maxPower).clamp(0.0, 1.0) * barsH;
      final x = leftPad + i * barW;
      canvas.drawRect(
        Rect.fromLTWH(x, topPad + barsH - h, barW * 0.85, h),
        Paint()..color = _bandColors[i],
      );
      // 频段名标签
      final tp = TextPainter(
        text: TextSpan(
          text: bandNames[i],
          style: TextStyle(fontSize: 9, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + (barW * 0.85 - tp.width) / 2, topPad + barsH + 2));
    }

    // ── 下半部分：3 认知指标 ──
    final metricsTop = topPad + barsH + bottomPad + gap;
    final metricW = plotW / 3;
    final m = metrics;
    final values = m == null
        ? const <double>[double.nan, double.nan, double.nan]
        : [m.focus, m.calm, m.sqi];

    for (var i = 0; i < 3; i++) {
      final cx = leftPad + i * metricW + metricW / 2;

      // 指标名
      final labelTp = TextPainter(
        text: TextSpan(
          text: _metricLabels[i],
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _metricColors[i]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(cx - labelTp.width / 2, metricsTop));

      // 数值
      final valStr = values[i].isFinite ? values[i].toStringAsFixed(2) : '--';
      final valTp = TextPainter(
        text: TextSpan(
          text: valStr,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTp.paint(canvas, Offset(cx - valTp.width / 2, metricsTop + 18));
    }
  }

  @override
  bool shouldRepaint(_SignalPainter old) =>
      old.block != block || old.metrics != metrics || old.maxPower != maxPower;
}
