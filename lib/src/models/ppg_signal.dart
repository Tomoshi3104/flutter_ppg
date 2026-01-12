enum SignalQuality { poor, fair, good }

class PPGSignal {
  final double rawIntensity;
  final double filteredIntensity;
  final List<double> rrIntervals;
  final SignalQuality quality;
  final DateTime timestamp;

  /// Indices of detected peaks in the current filtered window.
  /// Used for visualization of peak detection algorithm.
  final List<int> peakIndices;

  /// Signal-to-Noise Ratio in dB.
  final double snr;

  PPGSignal({
    required this.rawIntensity,
    required this.filteredIntensity,
    required this.rrIntervals,
    required this.quality,
    required this.timestamp,
    this.peakIndices = const [],
    this.snr = 0.0,
  });
}
