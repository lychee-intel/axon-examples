import 'package:axon_dart/axon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/filter_config.dart';

void main() {
  test('clears unused parameters for low/high-pass and notch filters', () {
    for (final kind in [FilterKind.lowPass, FilterKind.highPass]) {
      final stage = FilterEntry(kind: kind).toStage();
      expect(stage.cutoff2Hz, 0);
      expect(stage.q, 0);
    }
    final notch = FilterEntry(kind: FilterKind.notch, q: 30).toStage();
    expect(notch.cutoff2Hz, 0);
    expect(notch.q, 30);
  });
  test('creates a filter stage without resending stream sample rate', () {
    final stage = FilterEntry(
      kind: FilterKind.bandPass,
      cutoffHz: 8,
      cutoff2Hz: 30,
      order: 4,
      q: 0.7,
    ).toStage();

    expect(stage.kind, FilterKind.bandPass);
    expect(stage.cutoffHz, 8);
    expect(stage.cutoff2Hz, 30);
    expect(stage.order, 4);
    expect(stage.q, 0.7);
  });
}
