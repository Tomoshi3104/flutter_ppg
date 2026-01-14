import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'models/ppg_signal.dart';
import 'models/ppg_config.dart';
import 'signal_processor.dart';
import 'peak_detector.dart';
import 'quality_assessor.dart';
import 'outlier_filter.dart';
import 'frame_rate_detector.dart';
import 'rr_interval_analyzer.dart';
import 'models/filter_result.dart';
import 'utils/ring_buffer.dart';

/// Service to process camera images into PPG signals and RR intervals.
class FlutterPPGService {
  final PPGConfig config;
  final SignalProcessor _processor;
  final PeakDetector _peakDetector;
  final SignalQualityAssessor _qualityAssessor;
  final OutlierFilter _outlierFilter;
  final FrameRateDetector _frameRateDetector;
  final RRIntervalAnalyzer _rrAnalyzer;
  final bool _isCustomPeakDetector;

  // State
  late RingBuffer<double> _rawBuffer;
  late RingBuffer<double> _filteredBuffer;
  late PeakDetector _adaptivePeakDetector;
  int _adaptiveMinDistance = 0;
  double _adaptiveMinProminence = 0.0;
  final Stopwatch _frameStopwatch = Stopwatch();

  FlutterPPGService({
    this.config = const PPGConfig(),
    SignalProcessor? processor,
    PeakDetector? peakDetector,
    SignalQualityAssessor? qualityAssessor,
    OutlierFilter? outlierFilter,
    FrameRateDetector? frameRateDetector,
    RRIntervalAnalyzer? rrIntervalAnalyzer,
  }) : _processor = processor ?? const SignalProcessor(),
       _peakDetector = peakDetector ?? const PeakDetector(),
       _qualityAssessor =
           qualityAssessor ?? SignalQualityAssessor.fromConfig(config),
       _outlierFilter = outlierFilter ?? OutlierFilter.fromConfig(config),
       _frameRateDetector = frameRateDetector ?? FrameRateDetector(),
       _rrAnalyzer =
           rrIntervalAnalyzer ?? RRIntervalAnalyzer.fromConfig(config),
       _isCustomPeakDetector = peakDetector != null {
    // Initialize buffer based on config
    // 30 FPS * 10 seconds = 300 samples
    int capacity = (config.samplingRate * config.windowSizeSeconds).round();
    _rawBuffer = RingBuffer<double>(capacity);
    _filteredBuffer = RingBuffer<double>(capacity);
    if (_isCustomPeakDetector) {
      _adaptivePeakDetector = _peakDetector;
      _adaptiveMinDistance = _peakDetector.minDistance;
      _adaptiveMinProminence = _peakDetector.minProminence;
    } else {
      _adaptiveMinDistance =
          _minDistanceFromFps(config.samplingRate.toDouble());
      _adaptiveMinProminence = _peakDetector.minProminence;
      _adaptivePeakDetector = PeakDetector(
        minProminence: _adaptiveMinProminence,
        minDistance: _adaptiveMinDistance,
      );
    }
  }

  void dispose() {
    _rawBuffer.clear();
    _filteredBuffer.clear();
    _frameRateDetector.reset();
    _frameStopwatch.stop();
  }

  /// Returns the detected frame rate.
  double get detectedFPS => _frameRateDetector.fps;

  /// Returns true if frame rate detection has stabilized.
  bool get isFPSStable => _frameRateDetector.isStable;

  /// Processes a stream of camera images and yields PPG signals.
  Stream<PPGSignal> processImageStream(Stream<CameraImage> images) async* {
    await for (final image in images) {
      final now = DateTime.now();

      _frameRateDetector.recordFrameMicros(_nowMicros());
      final effectiveFPS = _effectiveFrameRate();
      _resizeBuffersIfNeeded(effectiveFPS);

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
      final minSamplesForQuality = effectiveFPS.round();
      if (!_rawBuffer.isFull && _rawBuffer.length < minSamplesForQuality) {
        // Need at least 1s of data
        yield PPGSignal(
          rawIntensity: intensity,
          filteredIntensity: 0.0,
          rrIntervals: [],
          quality: SignalQuality.poor,
          timestamp: now,
          peakIndices: [],
          snr: 0.0,
          frameRate: _frameRateDetector.fps,
          isFPSStable: _frameRateDetector.isStable,
        );
        continue;
      }

      final rawWindow = _rawBuffer.toList;

      // 4. Quality Assessment
      final quality = _qualityAssessor.assessQualityWithDrift(rawWindow, effectiveFPS);
      final driftRate = _qualityAssessor.calculateDriftRate(rawWindow, effectiveFPS);

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
          frameRate: _frameRateDetector.fps,
          isFPSStable: _frameRateDetector.isStable,
          driftRate: driftRate,
        );
        continue;
      }

      // 5. Filtering
      final filteredPoint = _processor.simpleBandpassFilter(rawWindow, 5);
      _filteredBuffer.add(filteredPoint);

      // 6. Peak Detection & RR Intervals
      if (!_frameRateDetector.isStable) {
        final snr = _qualityAssessor.calculateSNR(rawWindow);
        yield PPGSignal(
          rawIntensity: intensity,
          filteredIntensity: filteredPoint,
          rrIntervals: [],
          quality: quality,
          timestamp: now,
          peakIndices: const [],
          snr: snr,
          frameRate: _frameRateDetector.fps,
          isFPSStable: false,
          driftRate: driftRate,
          sdrr: 0.0,
          isSDRRAcceptable: false,
          rejectionRatio: 0.0,
          rejectedIntervalCount: 0,
        );
        continue;
      }

      final filteredWindow = _filteredBuffer.toList;
      final dynamicProminence = _dynamicMinProminence(filteredWindow);
      _updateAdaptivePeakDetector(effectiveFPS, dynamicProminence);
      final peakIndices = _adaptivePeakDetector.findPeaks(filteredWindow);

      // Map indices to local window time?
      // We need RR intervals.
      // Peaks are indices in the 'filteredWindow'.
      // Index N is 'now'. Index 0 is 'capacity' frames ago.

      List<double> rrIntervals = [];
      FilterResult filterResult = const FilterResult(intervals: [], totalInput: 0, rejectedCount: 0, rejectionRatio: 0.0);
      RRAnalysisResult rrAnalysis = _rrAnalyzer.analyze(const <double>[]);
      if (peakIndices.length >= 2) {
        final rawRRs = _adaptivePeakDetector.peaksToRRIntervals(peakIndices, effectiveFPS);
        filterResult = _outlierFilter.filterOutliersWithStats(rawRRs);
        rrIntervals = filterResult.intervals;
        rrAnalysis = _rrAnalyzer.analyze(rrIntervals);
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
        frameRate: _frameRateDetector.fps,
        isFPSStable: _frameRateDetector.isStable,
        driftRate: driftRate,
        sdrr: rrAnalysis.sdrr,
        isSDRRAcceptable: rrAnalysis.isSDRRAcceptable,
        rejectionRatio: filterResult.rejectionRatio,
        rejectedIntervalCount: filterResult.rejectedCount,
      );
    }
  }

  double _effectiveFrameRate() {
    final detected = _frameRateDetector.fps;
    if (detected <= 0) {
      return config.samplingRate.toDouble();
    }
    return detected;
  }

  void _resizeBuffersIfNeeded(double fps) {
    if (!_frameRateDetector.isStable) return;

    final desiredCapacity = (fps * config.windowSizeSeconds).round();
    if (desiredCapacity <= 0) return;
    if (_rawBuffer.capacity == desiredCapacity) return;

    final rawValues = _rawBuffer.toList;
    final filteredValues = _filteredBuffer.toList;

    final newRaw = RingBuffer<double>(desiredCapacity);
    final newFiltered = RingBuffer<double>(desiredCapacity);

    final rawStart = rawValues.length > desiredCapacity ? rawValues.length - desiredCapacity : 0;
    for (int i = rawStart; i < rawValues.length; i++) {
      newRaw.add(rawValues[i]);
    }

    final filteredStart = filteredValues.length > desiredCapacity ? filteredValues.length - desiredCapacity : 0;
    for (int i = filteredStart; i < filteredValues.length; i++) {
      newFiltered.add(filteredValues[i]);
    }

    _rawBuffer = newRaw;
    _filteredBuffer = newFiltered;
  }

  void _updateAdaptivePeakDetector(double fps, [double? minProminenceOverride]) {
    if (_isCustomPeakDetector) return;
    final minDistanceFrames = _minDistanceFromFps(fps);
    final minProminence = minProminenceOverride ?? _adaptiveMinProminence;
    final prominenceChanged = (minProminence - _adaptiveMinProminence).abs() >= 0.05;
    if (minDistanceFrames == _adaptiveMinDistance && !prominenceChanged) return;

    _adaptivePeakDetector = PeakDetector(
      minProminence: minProminence,
      minDistance: minDistanceFrames,
    );
    _adaptiveMinDistance = minDistanceFrames;
    _adaptiveMinProminence = minProminence;
  }

  int _minDistanceFromFps(double fps) {
    int minDistanceFrames = (fps * (config.minRRMs / 1000.0)).round();
    if (minDistanceFrames < 1) {
      minDistanceFrames = 1;
    }
    return minDistanceFrames;
  }

  int _nowMicros() {
    if (!_frameStopwatch.isRunning) {
      _frameStopwatch.start();
    }
    return _frameStopwatch.elapsedMicroseconds;
  }

  double _dynamicMinProminence(List<double> signal) {
    if (signal.length < 10) {
      return _adaptiveMinProminence > 0.0
          ? _adaptiveMinProminence
          : _peakDetector.minProminence;
    }
    final start = signal.length > 60 ? signal.length - 60 : 0;
    final stdDev = _calculateStdDev(signal.sublist(start));
    final computed = stdDev * 0.5;
    return computed < 0.2 ? 0.2 : computed;
  }

  double _calculateStdDev(List<double> values) {
    if (values.isEmpty) return 0.0;
    double sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    final mean = sum / values.length;
    double varianceSum = 0.0;
    for (final v in values) {
      final diff = v - mean;
      varianceSum += diff * diff;
    }
    final variance = varianceSum / values.length;
    return variance <= 0.0 ? 0.0 : math.sqrt(variance);
  }
}
