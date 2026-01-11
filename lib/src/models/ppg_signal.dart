enum SignalQuality { poor, fair, good }

class PPGSignal {
  final double rawIntensity;
  final double filteredIntensity;
  final List<double> rrIntervals;
  final SignalQuality quality;
  final DateTime timestamp;

  PPGSignal({required this.rawIntensity, required this.filteredIntensity, required this.rrIntervals, required this.quality, required this.timestamp});
}
