import 'models/filter_result.dart';
import 'models/ppg_config.dart';

/// Filters RR intervals to remove artifacts and noise.
class OutlierFilter {
  /// Minimum acceptable RR interval in milliseconds.
  /// Values below this are considered physiologically implausible and rejected.
  final double minRRMs;

  /// Maximum acceptable RR interval in milliseconds.
  /// Values above this are considered physiologically implausible and rejected.
  final double maxRRMs;

  /// Maximum allowed change ratio between adjacent RR intervals (0.0-1.0).
  /// Sudden changes exceeding this ratio are considered artifacts and rejected.
  /// For example, 0.30 means a 30% change is the maximum allowed.
  final double maxAdjacentChangeRatio;

  /// Creates an [OutlierFilter] with the specified thresholds.
  ///
  /// The following constraints must be satisfied (assertions will fail in debug mode):
  /// - [minRRMs] must be > 0
  /// - [maxRRMs] must be > [minRRMs]
  /// - [maxAdjacentChangeRatio] must be >= 0
  const OutlierFilter({required this.minRRMs, required this.maxRRMs, required this.maxAdjacentChangeRatio})
    : assert(minRRMs > 0),
      assert(maxRRMs > minRRMs),
      assert(maxAdjacentChangeRatio >= 0);

  /// Creates an [OutlierFilter] from a [PPGConfig].
  ///
  /// Uses the RR interval thresholds and change ratio from the configuration.
  factory OutlierFilter.fromConfig(PPGConfig config) {
    return OutlierFilter(minRRMs: config.minRRMs, maxRRMs: config.maxRRMs, maxAdjacentChangeRatio: config.maxAdjacentRRChangeRatio);
  }

  /// Filters outliers from RR intervals using Interquartile Range (IQR) method
  /// and physiological limits.
  ///
  /// Applies multiple filtering stages:
  /// 1. Physiological filter (removes values outside [minRRMs, maxRRMs])
  /// 2. Adjacent interval validation (removes sudden changes > maxAdjacentChangeRatio)
  /// 3. IQR method (removes statistical outliers)
  ///
  /// [rrIntervals] - List of RR intervals in milliseconds to filter.
  /// Returns a clean list of RR intervals that passed all filtering stages.
  List<double> filterOutliers(List<double> rrIntervals) {
    return filterOutliersWithStats(rrIntervals).intervals;
  }

  /// Filters outliers and returns filtering statistics.
  ///
  /// Same filtering process as [filterOutliers], but also returns statistics
  /// about how many intervals were rejected and the rejection ratio.
  ///
  /// [rrIntervals] - List of RR intervals in milliseconds to filter.
  /// Returns a [FilterResult] containing filtered intervals and statistics.
  FilterResult filterOutliersWithStats(List<double> rrIntervals) {
    if (rrIntervals.isEmpty) {
      return const FilterResult(intervals: [], totalInput: 0, rejectedCount: 0, rejectionRatio: 0.0);
    }

    int rejected = 0;
    final totalInput = rrIntervals.length;

    // 1. Physiological Filter
    var filtered = <double>[];
    for (final rr in rrIntervals) {
      if (rr >= minRRMs && rr <= maxRRMs) {
        filtered.add(rr);
      } else {
        rejected++;
      }
    }

    // 2. Adjacent interval validation
    if (filtered.length >= 2) {
      final adjacentFiltered = <double>[filtered[0]];
      for (int i = 1; i < filtered.length; i++) {
        final prev = adjacentFiltered.last;
        final curr = filtered[i];
        final changeRatio = (curr - prev).abs() / prev;

        if (changeRatio <= maxAdjacentChangeRatio) {
          adjacentFiltered.add(curr);
        } else {
          rejected++;
        }
      }
      filtered = adjacentFiltered;
    }

    // 3. IQR Filter
    if (filtered.length >= 4) {
      final beforeIQR = filtered.length;
      filtered = applyIQRMethod(filtered);
      rejected += beforeIQR - filtered.length;
    }

    return FilterResult(intervals: filtered, totalInput: totalInput, rejectedCount: rejected, rejectionRatio: totalInput > 0 ? rejected / totalInput : 0.0);
  }

  /// Applies the Interquartile Range (IQR) method to filter outliers.
  ///
  /// Outliers are defined as values falling outside [Q1 - 1.5*IQR, Q3 + 1.5*IQR],
  /// where Q1 is the first quartile, Q3 is the third quartile, and IQR = Q3 - Q1.
  ///
  /// [data] - List of values to filter.
  /// Returns a list containing only values within the acceptable range.
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
