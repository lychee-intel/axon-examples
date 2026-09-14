import 'dart:async';
import 'dart:typed_data';

import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_demo/waveform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('waveform paints when data arrives', (tester) async {
    final controller = StreamController<SampleBlock>.broadcast();
    // 关闭 debug 横幅：MaterialApp 的 CheckedModeBanner 自带一个 CustomPaint，
    // 会让 find.byType(CustomPaint) 命中 2 个，干扰对画布的断言。
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WaveformCanvas(stream: controller.stream, numChannels: 1),
    ));
    controller.add(SampleBlock(startTimestamp: 0, sampleRateHz: 250, numChannels: 1,
        numSamples: 100, data: Float32List(100)));
    await tester.pump();
    expect(find.byType(CustomPaint), findsOneWidget);
    controller.close();
  });
}
