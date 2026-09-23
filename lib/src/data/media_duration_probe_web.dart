import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

/// Web video probe outcome: exact duration plus a poster frame grabbed from
/// the clip (each null when the browser cannot decode that part).
typedef WebVideoProbe = ({double? durationSeconds, Uint8List? frameBytes});

/// Loads the picked video into a detached <video> element (wasm-safe via
/// package:web) once: [WebVideoProbe.durationSeconds] comes from the
/// metadata and [WebVideoProbe.frameBytes] is a JPEG poster frame captured
/// from the 0.1s mark for the composer preview card. Either field is null
/// when the browser cannot decode that part.
Future<WebVideoProbe> probeWebVideo(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes == null) return (durationSeconds: null, frameBytes: null);
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final video = web.HTMLVideoElement();
  // Safari refuses to decode unmuted media without a user gesture — keep
  // the probe element silent so off-gesture loads still work.
  video.muted = true;
  final ready = Completer<void>();
  video.onloadeddata = (web.Event _) {
    if (!ready.isCompleted) ready.complete();
  }.toJS;
  video.onerror = (web.Event _) {
    if (!ready.isCompleted) ready.complete();
  }.toJS;
  video.src = url;
  await ready.future.timeout(const Duration(seconds: 8), onTimeout: () {});

  final seconds = video.duration;
  if (video.readyState < web.HTMLMediaElement.HAVE_METADATA ||
      !seconds.isFinite) {
    web.URL.revokeObjectURL(url);
    return (durationSeconds: null, frameBytes: null);
  }

  // Nudge just past the first frame (often black on some codecs) and paint
  // the frame onto a canvas to extract a JPEG thumbnail.
  final frame = Completer<Uint8List?>();
  video.onseeked = (web.Event _) {
    if (frame.isCompleted) return;
    try {
      final canvas =
          web.document.createElement('canvas') as web.HTMLCanvasElement;
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      final ctx = canvas.getContext('2d');
      if (canvas.width == 0 || canvas.height == 0 || ctx == null) {
        frame.complete(null);
        return;
      }
      (ctx as web.CanvasRenderingContext2D).drawImage(video, 0, 0);
      final dataUrl = canvas.toDataURL('image/jpeg', 0.72.toJS);
      frame.complete(base64Decode(dataUrl.split(',').last));
    } catch (_) {
      frame.complete(null); // Tainted canvas / decode hiccup — no thumbnail.
    }
  }.toJS;
  video.currentTime = 0.1;
  final frameBytes = await frame.future
      .timeout(const Duration(seconds: 8), onTimeout: () => null);
  web.URL.revokeObjectURL(url);
  return (durationSeconds: seconds, frameBytes: frameBytes);
}

/// Back-compat shim for duration-only call sites.
Future<double?> probeWebVideoSeconds(PlatformFile file) =>
    probeWebVideo(file).then((p) => p.durationSeconds);
