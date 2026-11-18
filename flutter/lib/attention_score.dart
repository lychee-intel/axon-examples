import 'dart:math' as math;

import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';

enum AttentionScoreStatus {
  idle,
  waiting,
  fresh,
  held,
  stopped,
  suspended,
  error,
  failed,
}

/// Session-owned display history; switching views never interrupts collection.
class AttentionScoreHistory extends ChangeNotifier {
  final List<AttentionScoreEvent> _points = [];
  List<AttentionScoreEvent> get points => List.unmodifiable(_points);
  AttentionScoreStatus _status = AttentionScoreStatus.idle;
  AttentionScoreStatus get status => _status;
  String? _message;
  String? get message => _message;
  bool _accepting = false;
  bool _hasFresh = false;

  double? get currentScore =>
      _hasFresh && _points.isNotEmpty ? _points.last.score : null;

  void begin() {
    _clear();
    _accepting = true;
    _status = AttentionScoreStatus.waiting;
    notifyListeners();
  }

  void reset() {
    _clear();
    _accepting = false;
    _status = AttentionScoreStatus.idle;
    notifyListeners();
  }

  void stop() {
    _accepting = false;
    if (_status != AttentionScoreStatus.failed &&
        _status != AttentionScoreStatus.error) {
      _status = AttentionScoreStatus.stopped;
    }
    notifyListeners();
  }

  void fail(String message) {
    _clear();
    _message = message;
    _accepting = false;
    _status = AttentionScoreStatus.failed;
    notifyListeners();
  }

  void _clear() {
    _points.clear();
    _hasFresh = false;
    _message = null;
  }

  void add(AttentionScoreEvent event) {
    if (!_accepting) return;
    switch (event.kind) {
      case AttentionScoreEventKind.fresh:
      case AttentionScoreEventKind.heldArtifact:
        if (!event.score.isFinite || event.score < 0 || event.score > 100) {
          return;
        }
        if (_status == AttentionScoreStatus.suspended) return;
        if (_points.isNotEmpty && event.timestamp <= _points.last.timestamp) {
          _clear();
        } else if (_points.isNotEmpty &&
            event.timestamp - _points.last.timestamp > 2000001) {
          // Native scoring resets its retained value across sample gaps.
          _hasFresh = false;
        }
        _points.add(event);
        if (_points.length > 200) _points.removeAt(0);
        _hasFresh |= event.kind == AttentionScoreEventKind.fresh;
        _message = null;
        _status = event.kind == AttentionScoreEventKind.fresh
            ? AttentionScoreStatus.fresh
            : AttentionScoreStatus.held;
      case AttentionScoreEventKind.reset:
      case AttentionScoreEventKind.resumed:
        _clear();
        _status = AttentionScoreStatus.waiting;
      case AttentionScoreEventKind.suspended:
        _clear();
        _status = AttentionScoreStatus.suspended;
      case AttentionScoreEventKind.processingError:
        _clear();
        _message = event.message;
        _status = AttentionScoreStatus.error;
      case AttentionScoreEventKind.failed:
      case AttentionScoreEventKind.closed:
        _clear();
        _message = event.message;
        _status = AttentionScoreStatus.failed;
        _accepting = false;
    }
    notifyListeners();
  }
}

const _scoreColor = Color(0xFF168B83);
const _heldColor = Color(0xFFBC7416);

class AttentionScoreView extends StatelessWidget {
  const AttentionScoreView({super.key, required this.history});

  final AttentionScoreHistory history;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: history,
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final points = history.points;
      final status = switch (history.status) {
        AttentionScoreStatus.idle => '点击开始采集注意力分数',
        AttentionScoreStatus.waiting => '等待首个完整的 2 秒窗口',
        AttentionScoreStatus.fresh => '实时更新',
        AttentionScoreStatus.held =>
          history.currentScore == null ? '检测到伪迹，等待首个有效分数' : '检测到伪迹，保持上一分数',
        AttentionScoreStatus.stopped => '已停止 · 保留本轮曲线',
        AttentionScoreStatus.suspended => '设备已断开 · 等待恢复',
        AttentionScoreStatus.error => '计算暂不可用 · 等待新数据',
        AttentionScoreStatus.failed => '注意力分数不可用 · 请重新开始',
      };
      final color = switch (history.status) {
        AttentionScoreStatus.held => _heldColor,
        AttentionScoreStatus.error ||
        AttentionScoreStatus.failed => scheme.error,
        AttentionScoreStatus.fresh => _scoreColor,
        _ => scheme.onSurfaceVariant,
      };
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('注意力分数', style: theme.textTheme.titleMedium),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          history.currentScore?.toStringAsFixed(1) ?? '—',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(' / 100', style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ],
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(status, style: TextStyle(color: color)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '全 EEG 通道综合 · 每 2 秒更新 · 最近 200 个结果',
              style: theme.textTheme.bodySmall,
            ),
            if (history.message case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: RepaintBoundary(
                key: const ValueKey('attention-score-plot'),
                child: _ScorePlot(points: points),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              runSpacing: 4,
              children: [
                _legend('有效分数', _scoreColor),
                _legend('伪迹保持', _heldColor),
                Text('横轴：相对时间（秒）', style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 8, color: color),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _ScorePlot extends StatefulWidget {
  const _ScorePlot({required this.points});

  final List<AttentionScoreEvent> points;

  @override
  State<_ScorePlot> createState() => _ScorePlotState();
}

class _ScorePlotState extends State<_ScorePlot> {
  Offset? _cursor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onHover: (event) => setState(() => _cursor = event.localPosition),
      onExit: (_) => setState(() => _cursor = null),
      child: CustomPaint(
        size: Size.infinite,
        painter: _ScorePainter(
          points: widget.points,
          textColor: scheme.onSurfaceVariant,
          gridColor: scheme.outlineVariant,
          surfaceColor: scheme.surface,
          cursor: _cursor,
        ),
      ),
    );
  }
}

class _ScorePainter extends CustomPainter {
  _ScorePainter({
    required this.points,
    required this.textColor,
    required this.gridColor,
    required this.surfaceColor,
    required this.cursor,
  });

  final List<AttentionScoreEvent> points;
  final Color textColor;
  final Color gridColor;
  final Color surfaceColor;
  final Offset? cursor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const top = 28.0;
    final width = size.width - left - 16;
    final height = size.height - top - 28;
    if (width <= 0 || height <= 0) return;
    final plot = Rect.fromLTWH(left, top, width, height);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    void label(String text, Offset offset, {Color? color}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: color ?? textColor, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, offset);
    }

    double y(double value) => plot.bottom - value / 100 * height;
    for (final value in [0, 25, 50, 75, 100]) {
      canvas.drawLine(
        Offset(left, y(value.toDouble())),
        Offset(plot.right, y(value.toDouble())),
        grid,
      );
      label('$value', Offset(0, y(value.toDouble()) - 7));
    }
    final origin = points.isEmpty ? 0 : points.first.timestamp;
    final span = points.isEmpty
        ? 30.0
        : math.max(30.0, (points.last.timestamp - origin) / 1000000);
    double x(AttentionScoreEvent point) =>
        left + (point.timestamp - origin) / 1000000 / span * width;
    for (var i = 0; i <= 4; i++) {
      final fraction = i / 4;
      final dx = left + fraction * width;
      canvas.drawLine(Offset(dx, top), Offset(dx, plot.bottom), grid);
      label(
        '${(span * fraction).toStringAsFixed(0)}s',
        Offset((dx - 8).clamp(0, size.width - 30), plot.bottom + 8),
      );
    }
    canvas.save();
    // Include marker radii at the 0 and 100 endpoints.
    canvas.clipRect(plot.inflate(4));
    final line = Paint()
      ..color = _scoreColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final position = Offset(x(point), y(point.score));
      if (i > 0 && point.timestamp - points[i - 1].timestamp <= 2000001) {
        final previous = points[i - 1];
        canvas.drawLine(Offset(x(previous), y(previous.score)), position, line);
      }
      canvas.drawCircle(
        position,
        3,
        Paint()
          ..color = point.kind == AttentionScoreEventKind.heldArtifact
              ? _heldColor
              : _scoreColor,
      );
    }
    canvas.restore();
    if (cursor case final cursor?
        when points.isNotEmpty && plot.contains(cursor)) {
      final nearest = points.reduce(
        (a, b) => (x(a) - cursor.dx).abs() < (x(b) - cursor.dx).abs() ? a : b,
      );
      canvas.drawLine(
        Offset(x(nearest), top),
        Offset(x(nearest), plot.bottom),
        Paint()..color = textColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(left, 0, width, 24),
        Paint()..color = surfaceColor,
      );
      final held = nearest.kind == AttentionScoreEventKind.heldArtifact
          ? ' · 伪迹保持'
          : '';
      label(
        '${((nearest.timestamp - origin) / 1000000).toStringAsFixed(1)}s'
        ' · ${nearest.score.toStringAsFixed(1)} / 100$held',
        Offset(left, 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScorePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.cursor != cursor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.surfaceColor != surfaceColor;
}
