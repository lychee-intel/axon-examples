import 'dart:async';
import 'dart:typed_data';

import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/spectrum_canvas.dart';

void main() {
  testWidgets('spectrum canvas selects the source channel', (tester) async {
    final controller = StreamController<SpectrumBlock>.broadcast();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 150,
          child: SpectrumCanvas(stream: controller.stream, channel: 1),
        ),
      ),
    );
    SpectrumBlock block(int channel) => SpectrumBlock(
      channelIndex: channel,
      startTimestamp: 0,
      sampleRateHz: 250,
      fftSize: 2,
      numChannels: 1,
      numBins: 2,
      frequencies: Float32List.fromList([0, 125]),
      bins: Float32List.fromList([1, 2]),
    );
    dynamic painter() => tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(SpectrumCanvas),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter;
    controller.add(block(0));
    await tester.pump();
    expect(painter().block, isNull);
    final selected = block(1);
    controller.add(selected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(painter().block, same(selected));
    controller.add(block(2));
    await tester.pump();
    expect(painter().block, same(selected));
    await tester.pumpWidget(const SizedBox());
    await controller.close();
  });
}
