import 'package:axon_dart/axon.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/device_stream_config.dart';

void main() {
  test('selects EEG and retains provider sample rate and channel count', () {
    const motion = DeviceStreamInfo(
      id: 'motion',
      displayName: 'Motion',
      kind: 9,
      availability: 1,
      sampleRateHz: 100,
      numChannels: 6,
      samplingMode: SamplingMode.irregular,
    );
    const eeg = DeviceStreamInfo(
      id: 'eeg',
      displayName: 'EEG',
      kind: 0,
      availability: 1,
      sampleRateHz: 512,
      numChannels: 8,
    );

    final selected = selectDemoStream([motion, eeg]);

    expect(selected.id, 'eeg');
    expect(selected.sampleRateHz, 512);
    expect(selected.numChannels, 8);
  });

  test('rejects a selected irregular stream because this demo processes EEG', () {
    const motion = DeviceStreamInfo(
      id: 'motion',
      displayName: 'Motion',
      kind: 9,
      availability: 1,
      sampleRateHz: 100,
      numChannels: 6,
      samplingMode: SamplingMode.irregular,
    );

    expect(() => selectDemoStream([motion]), throwsUnsupportedError);
  });

  test('rejects devices without streams', () {
    expect(() => selectDemoStream(const []), throwsStateError);
  });

  test('rejects irregular EEG instead of assuming a nominal time axis', () {
    const eeg = DeviceStreamInfo(
      id: 'eeg', displayName: 'EEG', kind: 0, availability: 1,
      sampleRateHz: 250, numChannels: 3,
      samplingMode: SamplingMode.irregular,
    );
    expect(() => selectDemoStream([eeg]), throwsUnsupportedError);
  });
}
