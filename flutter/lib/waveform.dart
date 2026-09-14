import 'dart:async';
import 'dart:ui' as ui;

import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';

/// 通道颜色调色板（与 axon-debugger 保持一致）
const _palette = [
  Color(0xFF00CCCC),
  Color(0xFFCCCC00),
  Color(0xFFCC00CC),
  Color(0xFF00CC00),
  Color(0xFFCC6600),
  Color(0xFF6600CC),
  Color(0xFFCC0000),
  Color(0xFF0066CC),
];

/// 实时多通道波形画布：订阅 [stream] 的 SampleBlock，
/// 将所有通道纵向排列，每个通道占一个等高的条带。
class WaveformCanvas extends StatefulWidget {
  const WaveformCanvas({
    super.key,
    required this.stream,
    required this.numChannels,
    this.channelLabels,
    this.maxSeconds = 4,
  });

  final Stream<SampleBlock> stream;
  final int numChannels;
  final List<String>? channelLabels;
  final int maxSeconds;

  @override
  State<WaveformCanvas> createState() => _WaveformCanvasState();
}

/// 环形缓冲区：头部追加 O(1)，超容量时覆盖最旧数据，无 shift 开销。
/// 增量维护 min/max，避免每帧全量扫描。
class _RingBuffer {
  late final List<double> _buf;
  int _start = 0;
  int _len = 0;
  int capacity;
  double _min = double.infinity;
  double _max = double.negativeInfinity;

  _RingBuffer(this.capacity) {
    _buf = List<double>.filled(capacity, 0);
  }

  int get length => _len;
  double get min => _min;
  double get max => _max;

  void add(double v) {
    if (_len == capacity) {
      final old = _buf[_start];
      _buf[_start] = v;
      _start = (_start + 1) % capacity;
      // 被覆盖的值恰好是极值，或新值超出当前范围时重新扫描
      if (old <= _min || old >= _max || v < _min || v > _max) {
        _min = _buf[_start];
        _max = _buf[_start];
        for (var i = 1; i < _len; i++) {
          final s = _buf[(_start + i) % capacity];
          if (s < _min) _min = s;
          if (s > _max) _max = s;
        }
      }
    } else {
      _buf[(_start + _len) % capacity] = v;
      _len++;
      if (v < _min) _min = v;
      if (v > _max) _max = v;
    }
  }

  /// 批量写入：只保留最后 [capacity] 个样本，直接操作底层数组避免逐个 add 开销。
  void addSlice(List<double> source, int startIdx, int count, int stride) {
    if (count <= 0) return;
    // 计算实际需要保留的起始偏移：只保留最后 capacity 个
    final keep = count < capacity ? count : capacity;
    final skip = count - keep;
    final srcOffset = startIdx + skip * stride;

    // 如果会覆盖旧数据，先检查是否需要重算 min/max
    var needRecalc = false;
    if (_len == capacity && keep > 0) {
      // 检查被覆盖的区域是否包含当前 min/max
      for (var i = 0; i < keep; i++) {
        final oldPos = (_start + i) % capacity;
        final old = _buf[oldPos];
        if (old <= _min || old >= _max) {
          needRecalc = true;
          break;
        }
      }
    }

    for (var i = 0; i < keep; i++) {
      final v = source[srcOffset + i * stride];
      final pos = (_start + _len) % capacity;
      if (_len == capacity) {
        _buf[_start] = v;
        _start = (_start + 1) % capacity;
      } else {
        _buf[pos] = v;
        _len++;
      }
    }

    if (needRecalc) {
      // 重新扫描整个缓冲区
      _min = _buf[_start];
      _max = _buf[_start];
      for (var i = 1; i < _len; i++) {
        final s = _buf[(_start + i) % capacity];
        if (s < _min) _min = s;
        if (s > _max) _max = s;
      }
    } else {
      // 只对新写入的值更新 min/max
      for (var i = 0; i < keep; i++) {
        final v = source[srcOffset + i * stride];
        if (v < _min) _min = v;
        if (v > _max) _max = v;
      }
    }
  }

  double operator [](int index) => _buf[(_start + index) % capacity];
}

class _WaveformCanvasState extends State<WaveformCanvas> {
  StreamSubscription<SampleBlock>? _sub;
  final List<_RingBuffer> _channels = [];
  double _sampleRateHz = 250;
  int _frame = 0;
  // 帧率限制：最多每秒重绘 _maxFps 次，避免 CPU 浪费
  static const _maxFps = 60;
  DateTime _lastPaint = DateTime.fromMillisecondsSinceEpoch(0);
  bool _repaintScheduled = false;

  @override
  void initState() {
    super.initState();
    _initBuffers(250);
    _sub = widget.stream.listen(_onBlock);
  }

  @override
  void didUpdateWidget(covariant WaveformCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.numChannels != widget.numChannels) {
      _initBuffers(_sampleRateHz);
    }
  }

  void _initBuffers(double sampleRateHz) {
    final cap = (widget.maxSeconds * sampleRateHz).round();
    _channels.clear();
    for (var i = 0; i < widget.numChannels; i++) {
      _channels.add(_RingBuffer(cap));
    }
  }

  void _onBlock(SampleBlock block) {
    final nch = block.numChannels;
    final cap = (widget.maxSeconds * block.sampleRateHz).round();
    if (_channels.length != nch) {
      _channels.clear();
      for (var i = 0; i < nch; i++) {
        _channels.add(_RingBuffer(cap));
      }
    }
    _sampleRateHz = block.sampleRateHz;

    for (var c = 0; c < nch && c < _channels.length; c++) {
      final buf = _channels[c];
      if (buf.capacity != cap) {
        _channels[c] = _RingBuffer(cap);
      }
    }

    for (var c = 0; c < nch && c < _channels.length; c++) {
      _channels[c].addSlice(block.data, c, block.numSamples, nch);
    }
    _frame++;

    // 帧率限制：距离上次重绘不足 _maxFps 间隔时跳过
    if (!mounted || _repaintScheduled) return;
    final now = DateTime.now();
    final elapsed = now.difference(_lastPaint).inMicroseconds;
    final minInterval = 1000000 ~/ _maxFps; // 微秒
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
        painter: _WaveformPainter(
          channels: _channels,
          sampleRateHz: _sampleRateHz,
          maxSeconds: widget.maxSeconds,
          frame: _frame,
          channelLabels: widget.channelLabels,
          baselineColor: scheme.outlineVariant,
          textColor: scheme.onSurfaceVariant,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.channels,
    required this.sampleRateHz,
    required this.maxSeconds,
    required this.frame,
    this.channelLabels,
    required this.baselineColor,
    required this.textColor,
  });

  final List<_RingBuffer> channels;
  final double sampleRateHz;
  final int maxSeconds;
  final int frame;
  final List<String>? channelLabels;
  final Color baselineColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 48.0;
    const bottomPad = 20.0;
    const topPad = 2.0;
    final plotW = size.width - leftPad;
    final nch = channels.length;
    if (nch == 0 || plotW <= 0) return;
    final totalH = size.height - topPad - bottomPad;
    final trackH = totalH / nch;

    for (var c = 0; c < nch; c++) {
      final data = channels[c];
      final len = data.length;
      final trackTop = topPad + c * trackH;
      final trackMid = trackTop + trackH / 2;
      final color = _palette[c % _palette.length];

      // 通道分隔线
      if (c > 0) {
        canvas.drawLine(
          Offset(leftPad, trackTop),
          Offset(size.width, trackTop),
          Paint()..color = baselineColor..strokeWidth = 0.5,
        );
      }

      // baseline
      canvas.drawLine(
        Offset(leftPad, trackMid),
        Offset(size.width, trackMid),
        Paint()..color = const Color(0x4D4D4D4D)..strokeWidth = 0.5,
      );

      // 通道标签
      final label = (channelLabels != null && c < channelLabels!.length)
          ? channelLabels![c]
          : 'Ch${c + 1}';
      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 9, color: color),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(2, trackMid - labelPainter.height / 2),
      );

      if (len < 2) continue;

      // 使用环形缓冲区增量维护的 min/max（O(1)，无需全量扫描）
      var chMin = data.min;
      var chMax = data.max;
      if (!chMin.isFinite || !chMax.isFinite) continue;
      if ((chMax - chMin).abs() < 1e-12) {
        chMin -= 1.0;
        chMax += 1.0;
      }
      final range = chMax - chMin;
      final usableH = trackH * 0.8;
      final padY = (trackH - usableH) / 2;

      final trace = Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

      final totalPx = maxSeconds * sampleRateHz;
      final stepX = plotW / (totalPx - 1).clamp(1.0, 999999.0);
      final path = ui.Path();

      // 像素级降采样：当样本数 > 像素数时，每个 x 像素只取 min/max 两个点
      // 避免绘制不可见的多余线段，减少 Path 指令数
      final pixelCount = plotW.ceil();
      if (len > pixelCount * 2 && pixelCount > 0) {
        final samplesPerPx = len / pixelCount;
        var first = true;
        for (var px = 0; px < pixelCount; px++) {
          final si = (px * samplesPerPx).floor();
          final se = ((px + 1) * samplesPerPx).floor().clamp(0, len);
          // 找该像素范围内的 min/max
          var pMin = double.infinity;
          var pMax = double.negativeInfinity;
          for (var j = si; j < se; j++) {
            final v = data[j];
            if (v < pMin) pMin = v;
            if (v > pMax) pMax = v;
          }
          final x = leftPad + px * plotW / pixelCount;
          final yMin = trackTop + padY + (1 - (pMin - chMin) / range) * usableH;
          final yMax = trackTop + padY + (1 - (pMax - chMin) / range) * usableH;
          if (first) {
            path.moveTo(x, yMin);
            first = false;
          } else {
            path.lineTo(x, yMin);
          }
          if ((yMax - yMin).abs() > 0.5) {
            path.lineTo(x, yMax);
          }
        }
      } else {
        for (var i = 0; i < len; i++) {
          final x = leftPad + i * stepX;
          final y = trackTop + padY + (1 - (data[i] - chMin) / range) * usableH;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
      }
      canvas.drawPath(path, trace);
    }

    // ── 底部时间轴 ──
    final axisY = size.height - bottomPad + 12;
    canvas.drawLine(
      Offset(leftPad, axisY),
      Offset(size.width, axisY),
      Paint()..color = const Color(0x80505050)..strokeWidth = 0.5,
    );
    final totalSec = maxSeconds.toDouble();
    final tickStep = totalSec <= 4 ? 0.5 : 1.0;
    final numTicks = (totalSec / tickStep).floor();
    final tp = TextPainter(textDirection: ui.TextDirection.ltr);
    final tickStyle = TextStyle(fontSize: 9, color: textColor);
    for (var t = 0; t <= numTicks; t++) {
      final sec = t * tickStep;
      final x = leftPad + (sec / totalSec) * plotW;
      canvas.drawLine(
        Offset(x, axisY),
        Offset(x, axisY + 4),
        Paint()..color = textColor,
      );
      final label = tickStep < 1 ? '${sec.toStringAsFixed(1)}s' : '${sec.toInt()}s';
      tp.text = TextSpan(text: label, style: tickStyle);
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, axisY + 5));
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.frame != frame;
}
