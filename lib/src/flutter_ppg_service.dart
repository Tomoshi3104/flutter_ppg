import 'package:camera/camera.dart';
import 'models/ppg_signal.dart';

class FlutterPPGService {
  Stream<PPGSignal> processImageStream(Stream<CameraImage> images) async* {
    // TODO: Implement
    yield* Stream.empty();
  }

  PPGSignal processCameraFrame(CameraImage frame) {
    // TODO: Implement
    throw UnimplementedError();
  }
}
