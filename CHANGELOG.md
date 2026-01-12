# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2026-01-12

### Added

- Initial release of `flutter_ppg` package
- `FlutterPPGService` - Main orchestrator for PPG signal processing
- `SignalProcessor` - Red channel extraction and bandpass filtering
- `PeakDetector` - Heartbeat detection with minimum distance enforcement
- `SignalQualityAssessor` - Real-time signal quality assessment (Good/Fair/Poor)
- `OutlierFilter` - IQR-based outlier removal for RR intervals
- `RingBuffer` - Efficient sliding window utility
- Example app with:
  - Dual waveform visualization (Raw vs Filtered)
  - Peak markers on filtered signal
  - RR interval history display
  - Real-time SNR and quality stats
  - Start/Stop control with 30-second auto-timeout
