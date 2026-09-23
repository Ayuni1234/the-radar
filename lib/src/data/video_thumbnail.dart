import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'video_thumbnail_io.dart' if (dart.library.js_interop) 'video_thumbnail_stub.dart'
    as impl;

/// Native poster-frame extractor for device videos on mobile/desktop — a
/// real frame from the clip for the composer preview card, matching the
/// web canvas frame-grab. Method-channel plugins are unavailable on web,
/// so the conditional import compiles in a null-returning stub there and
/// on VMs without the native bindings.
///
/// Returns null when the platform cannot produce a frame (unsupported
/// format, missing plugin binding, extraction failure) — the caller shows
/// the icon placeholder instead. Never throws.
Future<Uint8List?> extractNativeVideoFrame(PlatformFile file) =>
    impl.extractNativeVideoFrame(file);
