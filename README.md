# Flutter PPG (Photoplethysmography)

A Flutter package for real-time camera-based PPG (Photoplethysmography) signal processing.
This package extracts the raw red channel intensity from camera frames, filters the signal to isolate cardiac activity, and detects heartbeats (RR intervals).

## ⚠️ Requirements

1.  **Hardware**: A device with a **Camera** and a **Flash (Torch)**.
2.  **Platform**: iOS or Android (Real device required, Simulator/Emulator usually cannot provide camera/flash access).

## 🚀 Getting Started

### 1. Installation

Add `flutter_ppg` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_ppg:
    path: ../ # Or your git/pub path
```

### 2. Basic Usage

Use the `FlutterPPGService` to process a stream of `CameraImage`s from the `camera` package.

```dart
// 1. Initialize Service
final ppgService = FlutterPPGService();

// 2. Start Camera Image Stream
// (Assuming standard camera controller setup)
controller.startImageStream((CameraImage image) {
  // Bridge to stream if necessary, or just use the service directly if updated
});

// Since the current API expects a Stream<CameraImage>, you can use a StreamController:
final streamController = StreamController<CameraImage>();
controller.startImageStream((image) => streamController.add(image));

// 3. Process Stream
ppgService.processImageStream(streamController.stream).listen((PPGSignal signal) {
  print('Quality: ${signal.quality}');
  print('Filtered Value: ${signal.filteredIntensity}');
  if (signal.rrIntervals.isNotEmpty) {
    print('Last RR: ${signal.rrIntervals.last} ms');
  }
});
```

See the `example/` directory for a complete working application.

## 👆 How to Measure

For accurate readings in the `example` app (or your implementation):

1.  **Enable Flash**: The back camera flash MUST be on (`FlashMode.torch`).
2.  **Cover Lens & Flash**: Place your fingertip gently over **both** the camera lens and the flash.
    - Do not press too hard (this restricts blood flow).
    - Do not press too ligthly (ambient light leaks in).
3.  **Stay Still**: Motion introduces significant noise. Keep your finger and the phone steady.

## 📦 Features

- **Signal Processing**:
  - Red channel extraction (optimized for YUV420/BGRA8888).
  - Bandpass filtering (0.7Hz - 3.0Hz) to isolate pulse.
  - Detrending to remove DC offset shifts.
- **Peak Detection**:
  - Robust local maxima detection with minimum distance enforcement.
  - Outlier rejection (IQR method) for cleaner RR intervals.
- **Quality Assessment**:
  - Real-time Signal Quality Index (Good/Fair/Poor).
  - Finger presence detection based on light intensity.

## 🧩 Architecture

The package follows clean architecture principles:

- `SignalProcessor`: Pure logic for math and filtering (Stateless).
- `PeakDetector`: Algorithms for identifying heartbeats.
- `SignalQualityAssessor`: Heuristics for signal validity.
- `FlutterPPGService`: Orchestrator (Stateful) managing the data flow and buffers.

## 📝 License

MIT
