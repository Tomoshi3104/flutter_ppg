import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  final List<double> signalData;
  final Color color;
  final double strokeWidth;

  /// Optional list of indices where peaks were detected.
  /// These will be marked on the waveform.
  final List<int> peakIndices;

  WaveformPainter({required this.signalData, this.color = Colors.redAccent, this.strokeWidth = 2.0, this.peakIndices = const []});

  @override
  void paint(Canvas canvas, Size size) {
    if (signalData.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final length = signalData.length;

    // Auto-scaling logic
    double minVal = signalData.reduce((a, b) => a < b ? a : b);
    double maxVal = signalData.reduce((a, b) => a > b ? a : b);

    // Add some padding to avoid clipping peaks
    final range = maxVal - minVal;
    final padding = range * 0.1;
    minVal -= padding;
    maxVal += padding;

    final scaleY = (maxVal == minVal) ? 1.0 : height / (maxVal - minVal);
    final stepX = width / (length - 1);

    for (int i = 0; i < length; i++) {
      final x = i * stepX;
      // Invert Y because canvas 0 is top
      final y = height - ((signalData[i] - minVal) * scaleY);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Draw peak markers
    if (peakIndices.isNotEmpty) {
      final peakPaint = Paint()
        ..color = Colors.yellowAccent
        ..style = PaintingStyle.fill;

      for (final peakIndex in peakIndices) {
        if (peakIndex >= 0 && peakIndex < length) {
          final x = peakIndex * stepX;
          final y = height - ((signalData[peakIndex] - minVal) * scaleY);
          canvas.drawCircle(Offset(x, y), 5.0, peakPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.signalData != signalData || oldDelegate.peakIndices != peakIndices || oldDelegate.color != color;
  }
}
