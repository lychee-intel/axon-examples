import 'package:axon_dart/axon.dart';

/// This demo's filters, analysis and waveform require uniformly sampled EEG.
DeviceStreamInfo selectDemoStream(List<DeviceStreamInfo> streams) {
  if (streams.isEmpty) throw StateError('Device has no streams');
  for (final stream in streams) {
    if (stream.kind == 0 && stream.samplingMode == SamplingMode.uniform) {
      return stream;
    }
  }
  throw UnsupportedError('Device has no uniformly sampled EEG stream');
}
