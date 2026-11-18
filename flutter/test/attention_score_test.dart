import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_demo/attention_score.dart';
import 'package:flutter_test/flutter_test.dart';

AttentionScoreEvent score(int timestamp, double value, {bool held = false}) =>
    AttentionScoreEvent(
      kind: held
          ? AttentionScoreEventKind.heldArtifact
          : AttentionScoreEventKind.fresh,
      timestamp: timestamp,
      score: value,
    );

void main() {
  test('history keeps the latest 200 results and their native timestamps', () {
    final history = AttentionScoreHistory()..begin();
    addTearDown(history.dispose);
    for (var i = 0; i < 210; i++) {
      history.add(score(i * 2000000, 60));
    }
    expect(history.points.length, 200);
    expect(history.points.first.timestamp, 20000000);
    expect(history.points.last.timestamp, 418000000);
  });

  test(
    'stop retains history, ignores late delivery, and restart clears it',
    () {
      final history = AttentionScoreHistory()..begin();
      addTearDown(history.dispose);
      history.add(score(0, 72.5));
      history.stop();
      history.add(score(2000000, 99));
      expect(history.points.single.score, 72.5);
      expect(history.status, AttentionScoreStatus.stopped);
      history.begin();
      expect(history.points, isEmpty);
      expect(history.currentScore, isNull);
      expect(history.status, AttentionScoreStatus.waiting);
    },
  );

  test('recoverable error clears stale scores and a fresh result recovers', () {
    final history = AttentionScoreHistory()..begin();
    addTearDown(history.dispose);
    history.add(score(0, 72.5));
    history.add(
      const AttentionScoreEvent(
        kind: AttentionScoreEventKind.processingError,
        message: 'invalid samples',
      ),
    );
    expect(history.points, isEmpty);
    expect(history.currentScore, isNull);
    expect(history.message, 'invalid samples');
    history.add(score(4000000, 65));
    expect(history.currentScore, 65);
    expect(history.message, isNull);
    history.add(
      const AttentionScoreEvent(kind: AttentionScoreEventKind.failed),
    );
    history.add(score(6000000, 99));
    expect(history.points, isEmpty);
    expect(history.status, AttentionScoreStatus.failed);
  });

  test(
    'suspension clears the readout and resumes with a complete new window',
    () {
      final history = AttentionScoreHistory()..begin();
      addTearDown(history.dispose);
      history.add(score(0, 72));
      history.add(
        const AttentionScoreEvent(kind: AttentionScoreEventKind.suspended),
      );
      expect(history.currentScore, isNull);
      expect(history.status, AttentionScoreStatus.suspended);
      history.add(
        const AttentionScoreEvent(kind: AttentionScoreEventKind.resumed),
      );
      expect(history.status, AttentionScoreStatus.waiting);
      history.add(score(8000000, 50));
      expect(history.points.single.timestamp, 8000000);
    },
  );

  test('initial artifacts are distinguished from a valid zero score', () {
    final history = AttentionScoreHistory()..begin();
    addTearDown(history.dispose);
    history.add(score(0, 0, held: true));
    expect(history.currentScore, isNull);
    expect(history.status, AttentionScoreStatus.held);
    history.add(score(2000000, 0));
    expect(history.currentScore, 0);
    history.add(score(4000000, 0, held: true));
    expect(history.currentScore, 0);
    expect(history.status, AttentionScoreStatus.held);
  });

  test('a held result after a missing window needs a new valid score', () {
    final history = AttentionScoreHistory()..begin();
    addTearDown(history.dispose);
    history.add(score(0, 70));
    history.add(score(6000000, 0, held: true));
    expect(history.currentScore, isNull);
    expect(history.points.length, 2);
    history.add(score(8000000, 50));
    expect(history.currentScore, 50);
  });

  test(
    'invalid scores are rejected and backwards timestamps start a new curve',
    () {
      final history = AttentionScoreHistory()..begin();
      addTearDown(history.dispose);
      history.add(score(4000000, 70));
      history.add(score(6000000, double.nan));
      history.add(score(6000000, 101));
      expect(history.points.length, 1);
      history.add(score(0, 50));
      expect(history.points.single.score, 50);
    },
  );

  testWidgets('view shows waiting, fresh, held and stopped readouts', (
    tester,
  ) async {
    final history = AttentionScoreHistory()..begin();
    addTearDown(history.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AttentionScoreView(history: history)),
      ),
    );
    expect(find.text('等待首个完整的 2 秒窗口'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    history.add(score(0, 72.5));
    await tester.pump();
    expect(find.text('72.5'), findsOneWidget);
    history.add(score(2000000, 72.5, held: true));
    await tester.pump();
    expect(find.text('检测到伪迹，保持上一分数'), findsOneWidget);
    history.stop();
    await tester.pump();
    expect(find.text('已停止 · 保留本轮曲线'), findsOneWidget);
    expect(find.text('72.5'), findsOneWidget);
    // Unmounting/recreating the view must not lose the session-owned history.
    await tester.pumpWidget(const SizedBox());
    history.begin();
    history.add(score(0, 40));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AttentionScoreView(history: history)),
      ),
    );
    expect(find.text('40.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('view fits a narrow desktop window and renders score endpoints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final history = AttentionScoreHistory()..begin();
    addTearDown(history.dispose);
    history.add(score(0, 0));
    history.add(score(2000000, 100));
    history.add(score(8000000, 60, held: true));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AttentionScoreView(history: history)),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('attention-score-plot')), findsOneWidget);
  });
}
