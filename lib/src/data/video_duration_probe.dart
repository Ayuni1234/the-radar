import 'dart:convert';
import 'dart:typed_data';

/// Pure-Dart MP4 duration probe for mobile/desktop builds.
///
/// Web validates the 3-minute rule with the DOM metadata probe; on IO
/// builds there is no `<video>` element to decode against, so the
/// pipeline used to fall back to a blunt 200 MB size guess — a 4-minute
/// clip sailed through. This parser reads the *actual* duration straight
/// from the MP4 `moov/mvhd` box (the same metadata every player shows),
/// no plugin, no codec support required.
///
/// Scoped to ISO-BMFF containers (`.mp4`/`.mov` — what phones record).
/// Anything unparsable (WebM, MKV, a truncated file) returns null and the
/// caller keeps its size-guard fallback — never throws.
///
/// Returns duration in seconds (fractional), or null when undeterminable.
double? mp4DurationSeconds(Uint8List bytes) {
  try {
    if (bytes.length < 16) return null;
    // 64-bit lengths are read as low/high 32-bit pairs so the probe works
    // identically on the web (dart2js/dart2wasm) and VM number models.
    final duration = _walkBoxes(bytes, 0, bytes.length, depth: 0);
    return duration;
  } catch (_) {
    return null;
  }
}

/// Walks ISO-BMFF boxes in [start, end) looking for `moov` (descend) and
/// `mvhd` (read duration). Depth-capped against malformed/deeply-nested
/// files; size 0 means "extends to end of range".
double? _walkBoxes(Uint8List b, int start, int end, {required int depth}) {
  if (depth > 4) return null;
  var offset = start;
  final bd = ByteData.sublistView(b);
  while (offset + 8 <= end) {
    final size32 = bd.getUint32(offset);
    final type = _fourCC(b, offset + 4);
    var header = 8;
    int size;
    if (size32 == 1) {
      if (offset + 16 > end) return null;
      final high = bd.getUint32(offset + 8);
      final low = bd.getUint32(offset + 12);
      size = low + high * 0x100000000; // dart2js/wasm-safe 64-bit length
      header = 16;
    } else if (size32 == 0) {
      size = end - offset; // box extends to the end of its parent
    } else {
      size = size32;
    }
    if (size < header || offset + size > end) return null; // corrupt

    if (type == 'mvhd') {
      final seconds = _readMvhd(b, offset + header, offset + size);
      if (seconds != null) return seconds;
    } else if (type == 'moov') {
      final nested = _walkBoxes(b, offset + header, offset + size,
          depth: depth + 1);
      if (nested != null) return nested;
    }
    offset += size;
  }
  return null;
}

/// `mvhd` payload: version 0 → timescale @12, duration @16 (u32 each);
/// version 1 → timescale @20 (u32), duration @24 (u64).
double? _readMvhd(Uint8List b, int start, int end) {
  if (end - start < 20) return null;
  final bd = ByteData.sublistView(b);
  final version = b[start];
  if (version == 1) {
    if (end - start < 32) return null;
    final timescale = bd.getUint32(start + 20);
    final high = bd.getUint32(start + 24);
    final low = bd.getUint32(start + 28);
    if (timescale == 0) return null;
    final duration = low + high * 0x100000000;
    return duration / timescale;
  }
  final timescale = bd.getUint32(start + 12);
  final duration = bd.getUint32(start + 16);
  if (timescale == 0) return null;
  return duration / timescale;
}

String _fourCC(Uint8List b, int offset) =>
    ascii.decode(b.sublist(offset, offset + 4), allowInvalid: true);
