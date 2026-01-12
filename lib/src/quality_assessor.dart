import 'dart:math' as math;
import 'package:flutter_ppg/src/models/ppg_signal.dart';

/// Assesses the quality of the PPG signal.
class SignalQualityAssessor {
  const SignalQualityAssessor();

  /// Checks if the finger is placed on the camera based on raw intensity.
  ///
  /// Heuristic:
  /// - Too dark (< 30): Finger removed or camera covered improperly.
  /// - Too bright (> 250): Flashlight causing saturation/blooming.
  /// - Good range: approx 60 - 240.
  bool isFingerPresent(double rawIntensity) {
    return rawIntensity > 30.0 && rawIntensity < 250.0;
  }

  /// Calculates Signal-to-Noise Ratio (SNR) in decibels (dB).
  ///
  /// [signal]: Recent signal window (e.g., last 1-2 seconds).
  double calculateSNR(List<double> signal) {
    if (signal.length < 2) return 0.0;

    // Signal Power = Variance of the signal
    final signalVariance = _calculateVariance(signal);
    if (signalVariance == 0) return 0.0; // Flatline

    // Noise Power = Variance of the first derivative (diff)
    // This assumes noise is high-frequency jitter.
    final diffs = <double>[];
    for (int i = 1; i < signal.length; i++) {
      diffs.add(signal[i] - signal[i - 1]);
    }
    final noiseVariance = _calculateVariance(diffs);

    if (noiseVariance == 0) return 100.0; // Perfect signal (no jitter)

    return 10 * math.log(signalVariance / noiseVariance) / math.ln10;
  }

  /// Determines overall signal quality.
  SignalQuality assessQuality(List<double> recentSignals) {
    if (recentSignals.isEmpty) return SignalQuality.poor;

    // 1. Check Intensity Saturation on the *latest* sample
    final last = recentSignals.last;
    if (!isFingerPresent(last)) {
      return SignalQuality.poor;
    }

    // 2. Check SNR (requires window)
    if (recentSignals.length < 30) {
      // Not enough data for robust stats
      return SignalQuality.fair;
    }

    final snr = calculateSNR(recentSignals);

    // Thresholds need tuning.
    // > 0 dB: Signal power > Noise power.
    // Typical good PPG might be 5-10 dB?
    if (snr > 5.0) return SignalQuality.good;
    if (snr > 0.0) return SignalQuality.fair;
    return SignalQuality.poor;
  }

  double _calculateVariance(List<double> data) {
    if (data.isEmpty) return 0.0;
    final mean = data.reduce((a, b) => a + b) / data.length;
    double sumSquaredDiff = 0.0;
    for (final x in data) {
      final diff = x - mean;
      sumSquaredDiff += diff * diff;
    }
    return sumSquaredDiff / data.length;
  }
}
