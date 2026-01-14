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

  /// Detected frame rate used for RR calculations.
  final double frameRate;

  /// Whether frame rate detection has stabilized.
  final bool isFPSStable;

  /// Baseline drift rate in intensity units per second.
  final double driftRate;

  /// Standard deviation of RR intervals (SDRR) in milliseconds.
  final double sdrr;

  /// Whether SDRR is within acceptable range (<150ms).
  final bool isSDRRAcceptable;

  /// Ratio of RR intervals rejected during filtering (0.0-1.0).
  final double rejectionRatio;

  /// Number of RR intervals rejected during filtering.
  final int rejectedIntervalCount;

  PPGSignal({
    required this.rawIntensity,
    required this.filteredIntensity,
    required this.rrIntervals,
    required this.quality,
    required this.timestamp,
    this.peakIndices = const [],
    this.snr = 0.0,
    this.frameRate = 30.0,
    this.isFPSStable = false,
    this.driftRate = 0.0,
    this.sdrr = 0.0,
    this.isSDRRAcceptable = true,
    this.rejectionRatio = 0.0,
    this.rejectedIntervalCount = 0,
  });
}
