import 'package:file_picker/file_picker.dart';

import 'media_duration_probe_stub.dart'
    if (dart.library.js_interop) 'media_duration_probe_web.dart' as impl;

/// Probes a picked video's exact duration in seconds. Real on web (DOM
/// metadata decode); null on VM/mobile, where the IO size guard applies.
Future<double?> probeWebVideoSeconds(PlatformFile file) =>
    impl.probeWebVideoSeconds(file);
