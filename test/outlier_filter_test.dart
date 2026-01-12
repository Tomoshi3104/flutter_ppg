import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ppg/src/outlier_filter.dart';

void main() {
  group('OutlierFilter', () {
    const filter = OutlierFilter();

    test('filterOutliers removes physiological impossible values', () {
      final input = [50.0, 800.0, 900.0, 2500.0, 1000.0];
      // 50 (too low, >300), 2500 (too high, <2000)
      final output = filter.filterOutliers(input);
      expect(output, containsAllInOrder([800.0, 900.0, 1000.0]));
      expect(output.length, 3);
    });

    test('applyIQRMethod removes statistical outliers', () {
      // Median ~100. Outlier 500.
      final input = [98.0, 99.0, 100.0, 101.0, 102.0, 500.0];

      // Sorted: 98, 99, 100, 101, 102, 500
      // Q1 (25%): index 1.25 -> mix of 99 and 100? or index based.
      // Q3 (75%): index 3.75 -> mix of 101 and 102?

      // Let's trust the calc. 1.5*IQR usually keeps the cluster.

      final output = filter.applyIQRMethod(input);
      expect(output, containsAll([98.0, 99.0, 100.0, 101.0, 102.0]));
      expect(output, isNot(contains(500.0)));
    });
  });
}
