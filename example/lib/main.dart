import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_ppg/flutter_ppg.dart';
import 'waveform_painter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.red, useMaterial3: true),
      home: const PPGExamplePage(),
    );
  }
}

class PPGExamplePage extends StatefulWidget {
  const PPGExamplePage({super.key});

  @override
  State<PPGExamplePage> createState() => _PPGExamplePageState();
}

class _PPGExamplePageState extends State<PPGExamplePage> {
  CameraController? _controller;
  final _ppgService = FlutterPPGService();

  // State for UI
  PPGSignal? _currentSignal;
  String _status = 'Initializing...';
  bool _isScanning = false;
  bool _isTransitioning = false; // Guard against rapid START/STOP
  int _timeLeft = 30;
  Timer? _timer;
  Timer? _uiUpdateTimer; // Throttle UI updates

  // Data buffers for visualization
  final List<double> _rawHistory = [];
  final List<double> _filteredHistory = [];
  final List<double> _rrHistory = [];
  List<int> _currentPeakIndices = [];
  static const int _historyLimit = 150;

  // Pending signal for throttled update
  PPGSignal? _pendingSignal;

  StreamController<CameraImage>? _imageStreamController;
  StreamSubscription<PPGSignal>? _ppgSubscription;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _status = 'No cameras found.');
        return;
      }
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);

      _controller = CameraController(camera, ResolutionPreset.low, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);

      await _controller!.initialize();
      if (mounted) {
        setState(() => _status = 'Ready. Press Start to measure.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Camera error: $e');
      }
    }
  }

  void _toggleScanning() {
    if (_isTransitioning) return; // Guard against rapid clicks
    if (_isScanning) {
      _stopProcessing();
    } else {
      _startProcessing();
    }
  }

  Future<void> _startProcessing() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isTransitioning) return;

    _isTransitioning = true;

    // Reset State
    setState(() {
      _isScanning = true;
      _timeLeft = 30;
      _rawHistory.clear();
      _filteredHistory.clear();
      _rrHistory.clear();
      _currentPeakIndices = [];
      _currentSignal = null;
      _pendingSignal = null;
      _status = 'Starting...';
    });

    try {
      await _controller!.setFlashMode(FlashMode.torch);
    } catch (e) {
      debugPrint('Flash error: $e');
    }

    // Start countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _isScanning) {
        setState(() => _timeLeft--);
        if (_timeLeft <= 0) {
          _stopProcessing();
        }
      }
    });

    // Start UI update timer (throttled to ~10fps instead of 30fps)
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _pendingSignal != null) {
        _applyPendingSignal();
      }
    });

    // Create stream controller
    _imageStreamController = StreamController<CameraImage>();

    try {
      await _controller!.startImageStream((image) {
        if (_imageStreamController != null && !_imageStreamController!.isClosed) {
          _imageStreamController!.add(image);
        }
      });
    } catch (e) {
      debugPrint('Image stream error: $e');
      _isTransitioning = false;
      await _stopProcessing();
      return;
    }

    // Subscribe to PPG service (NO setState here - just buffer the signal)
    _ppgSubscription = _ppgService.processImageStream(_imageStreamController!.stream).listen((signal) {
      _pendingSignal = signal;
      // Data buffering happens here (lightweight, no setState)
      _rawHistory.add(signal.rawIntensity);
      _filteredHistory.add(signal.filteredIntensity);
      if (_rawHistory.length > _historyLimit) _rawHistory.removeAt(0);
      if (_filteredHistory.length > _historyLimit) _filteredHistory.removeAt(0);
      _currentPeakIndices = signal.peakIndices;
      for (final rr in signal.rrIntervals) {
        _rrHistory.add(rr);
        if (_rrHistory.length > 20) _rrHistory.removeAt(0);
      }
    });

    _isTransitioning = false;
  }

  void _applyPendingSignal() {
    if (_pendingSignal == null) return;
    final signal = _pendingSignal!;
    _pendingSignal = null;

    setState(() {
      _currentSignal = signal;
      if (signal.quality == SignalQuality.good) {
        _status = 'Signal Good - Detecting...';
      } else if (signal.quality == SignalQuality.fair) {
        _status = 'Signal Fair - Keep steady';
      } else {
        _status = 'Signal Poor - Cover camera';
      }
    });
  }

  Future<void> _stopProcessing() async {
    if (_isTransitioning) return;
    _isTransitioning = true;

    _timer?.cancel();
    _timer = null;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    await _ppgSubscription?.cancel();
    _ppgSubscription = null;

    await _imageStreamController?.close();
    _imageStreamController = null;

    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('Stop camera error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isScanning = false;
        _status = 'Measurement Complete.';
      });
    }

    _isTransitioning = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _uiUpdateTimer?.cancel();
    _ppgSubscription?.cancel();
    _imageStreamController?.close();
    _controller?.dispose();
    _ppgService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String hrDisplay = '--';
    if (_rrHistory.isNotEmpty) {
      final rr = _rrHistory.last;
      if (rr > 0) {
        hrDisplay = '${(60000 / rr).round()}';
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Flutter PPG Demo')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCameraPreview(),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatsPanel(hrDisplay)),
                ],
              ),
              const SizedBox(height: 16),
              _buildWaveformCard(title: 'Raw Signal (Red Channel)', data: _rawHistory, color: Colors.red.shade300, peakIndices: []),
              const SizedBox(height: 12),
              _buildWaveformCard(title: 'Filtered Signal (Bandpass)', data: _filteredHistory, color: Colors.greenAccent, peakIndices: _currentPeakIndices),
              const SizedBox(height: 12),
              _buildRRHistoryCard(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isTransitioning ? null : _toggleScanning,
        backgroundColor: _isTransitioning ? Colors.grey : (_isScanning ? Colors.red : Colors.green),
        icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
        label: Text(_isScanning ? 'STOP' : 'START'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildCameraPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(
        height: 100,
        width: 100,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.shade800),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      height: 100,
      width: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _getQualityColor(), width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: CameraPreview(_controller!),
    );
  }

  Widget _buildStatsPanel(String hrDisplay) {
    final snr = _currentSignal?.snr ?? 0.0;
    final quality = _currentSignal?.quality ?? SignalQuality.poor;
    final peakCount = _currentPeakIndices.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$hrDisplay BPM',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _getQualityColor()),
                ),
                if (_isScanning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                    child: Text('$_timeLeft s'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_status, style: TextStyle(color: _getQualityColor())),
            const SizedBox(height: 8),
            Text('Quality: ${quality.name.toUpperCase()} | SNR: ${snr.toStringAsFixed(1)} dB', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text('Peaks: $peakCount', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveformCard({required String title, required List<double> data, required Color color, required List<int> peakIndices}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: CustomPaint(
                painter: WaveformPainter(signalData: data, color: color, peakIndices: peakIndices),
                child: Container(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRRHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RR Intervals (ms)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            if (_rrHistory.isEmpty)
              const Text('Waiting for data...', style: TextStyle(color: Colors.white54))
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _rrHistory.map((rr) {
                  final isOutlier = rr < 400 || rr > 1500;
                  return Chip(
                    label: Text('${rr.round()}'),
                    backgroundColor: isOutlier ? Colors.orange.shade800 : Colors.green.shade800,
                    labelStyle: const TextStyle(fontSize: 11),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Color _getQualityColor() {
    if (!_isScanning) return Colors.grey;
    if (_currentSignal == null) return Colors.grey;
    switch (_currentSignal!.quality) {
      case SignalQuality.good:
        return Colors.greenAccent;
      case SignalQuality.fair:
        return Colors.orangeAccent;
      case SignalQuality.poor:
        return Colors.redAccent;
    }
  }
}
