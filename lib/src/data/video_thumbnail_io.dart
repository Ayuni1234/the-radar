import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Native extraction on mobile/desktop. The picked video streams from its
/// [PlatformFile.path] — no path (e.g. an odd web-style bytes-only pick on
/// a VM) means no frame. A ~0.1s frame matches the web probe's choice of
/// just past the first frame, which some codecs render black.
Future<Uint8List?> extractNativeVideoFrame(PlatformFile file) async {
  if (kIsWeb) return null;
  final path = file.path;
  if (path == null || path.isEmpty) return null;
  try {
    return await VideoThumbnail.thumbnailData(
      video: path,
      imageFormat: ImageFormat.JPEG,
      // Preview-card scale; height auto-scales to the source aspect ratio.
      maxWidth: 256,
      quality: 72,
      timeMs: 100,
    );
  } catch (e) {
    debugPrint('[Media] native thumbnail extraction failed: $e');
    return null;
  }
}
