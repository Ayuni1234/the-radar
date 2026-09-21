import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Web: file_picker already loaded the bytes into memory (withData: true).
Future<Uint8List?> readFileBytes(PlatformFile file) async => file.bytes;
