import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'read_file_bytes_stub.dart'
    if (dart.library.io) 'read_file_bytes_mobile.dart' as impl;

/// Reads the full bytes of a picked file for upload. Web uses the picker's
/// in-memory bytes; IO streams from the on-disk path. Null = unreadable.
Future<Uint8List?> readFileBytes(PlatformFile file) => impl.readFileBytes(file);
