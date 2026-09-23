import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Web (and any VM without the native plugin bindings) cannot run the
/// method-channel extractor — return null so the UI falls back to the
/// icon placeholder. Web has its own canvas frame-grab instead.
Future<Uint8List?> extractNativeVideoFrame(PlatformFile file) async => null;
