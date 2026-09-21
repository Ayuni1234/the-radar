import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// IO (mobile/desktop): stream the bytes from the picked file's path.
Future<Uint8List?> readFileBytes(PlatformFile file) async {
  final path = file.path;
  if (path == null) return null;
  return File(path).readAsBytes();
}
