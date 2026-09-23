import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'media_duration_probe_stub.dart'
    if (dart.library.js_interop) 'media_duration_probe_web.dart' as impl;

/// Probe outcome for a picked video: exact duration in seconds plus a JPEG
/// poster frame for the composer preview card. On VM/mobile there is no DOM
/// to decode against, so both fields are null (frame falls back to the
/// video-icon placeholder in the UI).
typedef WebVideoProbe = ({double? durationSeconds, Uint8List? frameBytes});

/// Full probe: real on web (DOM metadata decode + canvas frame grab); nulls
/// on VM/mobile, where the IO size guard applies instead.
Future<WebVideoProbe> probeWebVideo(PlatformFile file) =>
    impl.probeWebVideo(file);

/// Probes a picked video's exact duration in seconds. Real on web; null on
/// VM/mobile, where the IO size guard applies.
Future<double?> probeWebVideoSeconds(PlatformFile file) =>
    impl.probeWebVideoSeconds(file);
