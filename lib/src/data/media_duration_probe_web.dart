import 'dart:async';
import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

/// Reads the exact duration of a picked video on web by loading it into a
/// detached <video> element (wasm-safe via package:web). Returns null when
/// the browser cannot decode metadata.
Future<double?> probeWebVideoSeconds(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes == null) return null;
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final video = web.HTMLVideoElement();
  final completer = Completer<double?>();
  video.onloadedmetadata = (web.Event _) {
    if (!completer.isCompleted) completer.complete(video.duration);
  }.toJS;
  video.onerror = (web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }.toJS;
  video.src = url;
  final seconds = await completer.future.timeout(
    const Duration(seconds: 8),
    onTimeout: () => null,
  );
  web.URL.revokeObjectURL(url);
  return seconds;
}
