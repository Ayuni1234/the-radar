import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// VM/mobile stub: there is no DOM to probe durations or grab frames
/// against. The IO path relies on the size guard in [MediaUploadService]
/// instead.
Future<({double? durationSeconds, Uint8List? frameBytes})> probeWebVideo(
        PlatformFile file) async =>
    (durationSeconds: null, frameBytes: null);

/// Back-compat shim: duration-only probe (null on VM/mobile).
Future<double?> probeWebVideoSeconds(PlatformFile file) async => null;
