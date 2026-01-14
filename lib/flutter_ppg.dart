export 'src/flutter_ppg_service.dart';
export 'src/models/ppg_signal.dart';
export 'src/models/ppg_config.dart';
export 'src/frame_rate_detector.dart';
export 'src/rr_interval_analyzer.dart';
export 'src/models/filter_result.dart';

// Exporting low-level components for advanced usage or testing?
// Maybe keep them internal for now to keep API surface clean (KISS).
// But user plan showed them in `lib/src`, not `lib/src/internal`.
// If they are in `lib/src` but not exported here, they are protected.
// Let's stick to exposing the Service and Models primarily.
