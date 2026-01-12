/// Filters RR intervals to remove artifacts and noise.
class OutlierFilter {
  const OutlierFilter();

  // Physiological limits for RR intervals (in ms)
  // 300ms = 200 BPM (Max HR)
  // 2000ms = 30 BPM (Min HR)
  static const double minRR = 300.0;
  static const double maxRR = 2000.0;

  /// Filters outliers from [rrIntervals] using Interquartile Range (IQR) method
  /// and physiological limits.
  ///
  /// returns a clean list of RR intervals.
  List<double> filterOutliers(List<double> rrIntervals) {
    if (rrIntervals.length < 4) return rrIntervals;

    // 1. Physiological Filter first (Fast reject)
    final physioFiltered = rrIntervals.where((rr) => rr >= minRR && rr <= maxRR).toList();

    if (physioFiltered.length < 4) return physioFiltered;

    // 2. IQR Filter
    return applyIQRMethod(physioFiltered);
  }

  /// Applies the IQR method to filter outliers.
  ///
  /// Outliers are defined as values falling outside [Q1 - 1.5*IQR, Q3 + 1.5*IQR].
  List<double> applyIQRMethod(List<double> data) {
    if (data.isEmpty) return [];

    final sorted = List<double>.from(data)..sort();
    final q1 = _percentile(sorted, 25);
    final q3 = _percentile(sorted, 75);
    final iqr = q3 - q1;

    final lowerBound = q1 - 1.5 * iqr;
    final upperBound = q3 + 1.5 * iqr;

    return data.where((val) => val >= lowerBound && val <= upperBound).toList();
  }

  double _percentile(List<double> sortedData, int percentile) {
    if (sortedData.isEmpty) return 0.0;

    final n = sortedData.length;
    final index = (percentile / 100) * (n - 1);
    final lower = index.floor();
    final upper = index.ceil();

    if (lower == upper) {
      return sortedData[lower];
    }

    final weight = index - lower;
    return sortedData[lower] * (1 - weight) + sortedData[upper] * weight;
  }
}
