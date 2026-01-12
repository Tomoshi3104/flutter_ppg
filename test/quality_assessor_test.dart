import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ppg/src/quality_assessor.dart';
import 'dart:math' as math;
import 'package:flutter_ppg/src/models/ppg_signal.dart';

void main() {
  group('SignalQualityAssessor', () {
    const assessor = SignalQualityAssessor();

    test('isFingerPresent checks bounds', () {
      expect(assessor.isFingerPresent(10.0), false); // Too dark
      expect(assessor.isFingerPresent(100.0), true); // Good
      expect(assessor.isFingerPresent(255.0), false); // Saturated
    });

    test('calculateSNR estimates signal quality', () {
      // Clean sine wave
      final sine = List.generate(100, (i) => 10.0 * math.sin(i * 0.1)); // Very smooth
      final snrSine = assessor.calculateSNR(sine);
      expect(snrSine, greaterThan(10.0)); // Should be high

      // Noise
      final noise = List.generate(100, (i) => (i % 2 == 0) ? 1.0 : -1.0); // High freq sawtooth
      final snrNoise = assessor.calculateSNR(noise);
      expect(snrNoise, lessThan(10.0)); // Should be lower
    });

    test('assessQuality delegates to metrics', () {
      // Short weak signal
      final weak = [10.0, 10.0];
      expect(assessor.assessQuality(weak), SignalQuality.poor);

      // Saturated
      final saturated = [255.0];
      expect(assessor.assessQuality(saturated), SignalQuality.poor);
    });
  });
}
