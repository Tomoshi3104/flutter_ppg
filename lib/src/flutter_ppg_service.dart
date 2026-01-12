import 'dart:async';
import 'package:camera/camera.dart';
import 'models/ppg_signal.dart';
import 'models/ppg_config.dart';
import 'signal_processor.dart';
import 'peak_detector.dart';
import 'quality_assessor.dart';
import 'outlier_filter.dart';
import 'utils/ring_buffer.dart';

/// Service to process camera images into PPG signals and RR intervals.
class FlutterPPGService {
  final PPGConfig config;
  final SignalProcessor _processor;
  final PeakDetector _peakDetector;
  final SignalQualityAssessor _qualityAssessor;
  final OutlierFilter _outlierFilter;

  // State
  late final RingBuffer<double> _rawBuffer;
  late final RingBuffer<double> _filteredBuffer;

  FlutterPPGService({
    this.config = const PPGConfig(),
    SignalProcessor? processor,
    PeakDetector? peakDetector,
    SignalQualityAssessor? qualityAssessor,
    OutlierFilter? outlierFilter,
  }) : _processor = processor ?? const SignalProcessor(),
       _peakDetector = peakDetector ?? const PeakDetector(),
       _qualityAssessor = qualityAssessor ?? const SignalQualityAssessor(),
       _outlierFilter = outlierFilter ?? const OutlierFilter() {
    // Initialize buffer based on config
    // 30 FPS * 10 seconds = 300 samples
    int capacity = (config.samplingRate * config.windowSizeSeconds).round();
    _rawBuffer = RingBuffer<double>(capacity);
    _filteredBuffer = RingBuffer<double>(capacity);
  }

  void dispose() {
    _rawBuffer.clear();
    _filteredBuffer.clear();
  }

  /// Processes a stream of camera images and yields PPG signals.
  Stream<PPGSignal> processImageStream(Stream<CameraImage> images) async* {
    await for (final image in images) {
      final now = DateTime.now();

      // 1. Extract Signal
      double intensity;
      try {
        intensity = _processor.extractRedChannel(image);
      } catch (e) {
        // Skip frame on error
        continue;
      }

      // 2. Update Raw Buffer
      _rawBuffer.add(intensity);

      // 3. Early Exit if filling buffer
      if (!_rawBuffer.isFull && _rawBuffer.length < config.samplingRate) {
        // Need at least 1s of data
        yield PPGSignal(
          rawIntensity: intensity,
          filteredIntensity: 0.0,
          rrIntervals: [],
          quality: SignalQuality.poor,
          timestamp: now,
          peakIndices: [],
          snr: 0.0,
        );
        continue;
      }

      final rawWindow = _rawBuffer.toList;

      // 4. Quality Assessment
      final quality = _qualityAssessor.assessQuality(rawWindow);

      if (quality == SignalQuality.poor) {
        // Even if poor, we might want to feed the filter to keep state?
        // Or just reset?
        // Let's add 0 to filtered buffer to maintain time alignment roughly,
        // or just add the raw trend.
        // Better: Calculate filter anyway to keep continuity if signal recovers.

        final filteredPoint = _processor.simpleBandpassFilter(rawWindow, 5);
        _filteredBuffer.add(filteredPoint);

        yield PPGSignal(
          rawIntensity: intensity,
          filteredIntensity: filteredPoint,
          rrIntervals: [],
          quality: SignalQuality.poor,
          timestamp: now,
          peakIndices: [],
          snr: _qualityAssessor.calculateSNR(rawWindow),
        );
        continue;
      }

      // 5. Filtering
      final filteredPoint = _processor.simpleBandpassFilter(rawWindow, 5);
      _filteredBuffer.add(filteredPoint);

      // 6. Peak Detection & RR Intervals
      final filteredWindow = _filteredBuffer.toList;
      final peakIndices = _peakDetector.findPeaks(filteredWindow);

      // Map indices to local window time?
      // We need RR intervals.
      // Peaks are indices in the 'filteredWindow'.
      // Index N is 'now'. Index 0 is 'capacity' frames ago.

      List<double> rrIntervals = [];
      if (peakIndices.length >= 2) {
        final rawRRs = _peakDetector.peaksToRRIntervals(peakIndices, config.samplingRate.toDouble());
        rrIntervals = _outlierFilter.filterOutliers(rawRRs);
      }

      final snr = _qualityAssessor.calculateSNR(rawWindow);

      yield PPGSignal(
        rawIntensity: intensity,
        filteredIntensity: filteredPoint,
        rrIntervals: rrIntervals,
        quality: quality,
        timestamp: now,
        peakIndices: peakIndices,
        snr: snr,
      );
    }
  }
}
