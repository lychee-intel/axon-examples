import 'dart:async';

import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';

/// 实时频谱画布：订阅 [stream] 的 SpectrumBlock，把 [channel] 通道的 bins
/// 画成柱状图，X 轴为频率（Hz）、Y 轴为振幅/功率密度。
class SpectrumCanvas extends StatefulWidget {
  const SpectrumCanvas({
    super.key,
    required this.stream,
    this.channel = 0,
  });

  final Stream<SpectrumBlock> stream;
  final int channel;

  @override
  State<SpectrumCanvas> createState() => _SpectrumCanvasState();
}

class _SpectrumCanvasState extends State<SpectrumCanvas> {
  StreamSubscription<SpectrumBlock>? _sub;
  SpectrumBlock? _last;
  double _maxY = 0;
  // 帧率限制：最多每秒重绘 30 次（频谱变化慢，不需要60fps）
  static const _maxFps = 30;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
  bool _repaintScheduled = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen(_onBlock);
  }

  void _onBlock(SpectrumBlock block) {
    final ch = widget.channel.clamp(0, block.numChannels - 1);
    final nb = block.numBins;
    var max = 0.0;
    for (var k = 0; k < nb; k++) {
      final v = block.bins[ch * nb + k];
      if (v > max) max = v;
    }
    _last = block;
    _maxY = max.isFinite && max > 0 ? max : 1.0;

    // 帧率限制
    if (!mounted || _repaintScheduled) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastPaint).inMicroseconds;
    final minInterval = 1000000 ~/ _maxFps;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SpectrumPainter(
          block: _last,
          channel: widget.channel,
          maxY: _maxY,
          barColor: scheme.primary,
          textColor: scheme.onSurfaceVariant,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.block,
    required this.channel,
    required this.maxY,
    required this.barColor,
    required this.textColor,
  });

  final SpectrumBlock? block;
  final int channel;
  final double maxY;
  final Color barColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final b = block;
    if (b == null) return;

    const leftPad = 8.0;
    const bottomPad = 18.0;
    const topPad = 4.0;
    final plotW = size.width - leftPad;
    final plotH = size.height - topPad - bottomPad;
    if (plotW <= 0 || plotH <= 0) return;

    final nb = b.numBins;
    final ch = channel.clamp(0, b.numChannels - 1); // 通道主序首 bin 下标
    final barW = plotW / nb;

    final paint = Paint()..color = barColor;
    for (var k = 0; k < nb; k++) {
      final v = b.bins[ch * nb + k];
      final h = (v / maxY).clamp(0.0, 1.0) * plotH;
      final x = leftPad + k * barW;
      canvas.drawRect(
        Rect.fromLTWH(x, topPad + plotH - h, barW * 0.9, h),
        paint,
      );
    }

    // X 轴频率标注：0、中点、Nyquist
    final tp = TextPainter(
      text: TextSpan(
        text: '0 Hz',
        style: TextStyle(fontSize: 10, color: textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(leftPad, topPad + plotH + 2));

    final nyq = b.frequencies.last;
    final mid = TextPainter(
      text: TextSpan(
        text: '${(nyq / 2).toStringAsFixed(0)} Hz',
        style: TextStyle(fontSize: 10, color: textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    mid.paint(canvas, Offset(leftPad + plotW / 2 - mid.width / 2, topPad + plotH + 2));

    final nyqT = TextPainter(
      text: TextSpan(
        text: '${nyq.toStringAsFixed(0)} Hz',
        style: TextStyle(fontSize: 10, color: textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    nyqT.paint(canvas, Offset(leftPad + plotW - nyqT.width, topPad + plotH + 2));
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      oldDelegate.block != block ||
      oldDelegate.channel != channel ||
      oldDelegate.maxY != maxY;
}
