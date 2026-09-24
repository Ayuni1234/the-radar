import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:the_radar/src/data/video_duration_probe.dart';
import 'package:the_radar/src/data/media_upload_service.dart'
    show MediaUploadService, maxVideoDuration;

/// Builds a minimal ISO-BMFF file: [boxes] of (type, payload) nested one
/// level inside an optional parent.
Uint8List _mp4({required int timescale, required int duration, int version = 0}) {
  void putU32(BytesBuilder b, int v) {
    final x = ByteData(4)..setUint32(0, v);
    b.add(x.buffer.asUint8List());
  }

  void putU64(BytesBuilder b, int v) {
    final x = ByteData(8)..setUint64(0, v);
    b.add(x.buffer.asUint8List());
  }

  // mvhd payload: version/flags, (creation, modification), timescale,
  // duration (u32 for v0; u64 for v1), rate/volume etc. (truncated ok —
  // the parser only reads the header fields).
  final mvhd = BytesBuilder();
  mvhd.addByte(version);
  mvhd.add([0, 0, 0]); // flags
  putU32(mvhd, 0); // creation
  putU32(mvhd, 0); // modification
  if (version == 1) {
    // v1 widens creation/modification to 64-bit before timescale.
    putU32(mvhd, 0);
    putU32(mvhd, 0);
  }
  putU32(mvhd, timescale);
  if (version == 1) {
    putU64(mvhd, duration);
  } else {
    putU32(mvhd, duration);
  }
  mvhd.add(List<int>.filled(40, 0)); // rate/volume/… trailer

  Uint8List box(String type, List<int> payload) {
    final b = BytesBuilder();
    putU32(b, 8 + payload.length);
    b.add(type.codeUnits);
    b.add(payload);
    return b.toBytes();
  }

  Uint8List container(String type, List<int> children) {
    final b = BytesBuilder();
    putU32(b, 8 + children.length);
    b.add(type.codeUnits);
    b.add(children);
    return b.toBytes();
  }

  final moov = container('moov', box('mvhd', mvhd.toBytes()));
  final ftyp = box('ftyp', 'isom'.codeUnits);
  final out = BytesBuilder();
  out.add(ftyp);
  out.add(moov);
  return out.toBytes();
}

void main() {
  group('mp4DurationSeconds (mobile/desktop 3-min enforcement)', () {
    test('parses a v0 mvhd box: 120 s at 1000 timescale', () {
      final bytes = _mp4(timescale: 1000, duration: 120000);
      final seconds = mp4DurationSeconds(bytes);
      expect(seconds, isNotNull);
      expect(seconds!, closeTo(120.0, 0.001));
    });

    test('parses a v1 (64-bit duration) mvhd box: 181 s — over the cap', () {
      final bytes = _mp4(
          timescale: 44100, duration: 181 * 44100, version: 1);
      final seconds = mp4DurationSeconds(bytes);
      expect(seconds, isNotNull);
      // A 3-minute-and-one clip must be measurable so the service rejects it.
      expect(seconds!, greaterThan(maxVideoDuration.inSeconds));
    });

    test('exactly 180 s passes the documented limit', () {
      final bytes = _mp4(timescale: 1000, duration: 180000);
      final seconds = mp4DurationSeconds(bytes);
      expect(seconds, isNotNull);
      expect(seconds!, lessThanOrEqualTo(180.0));
    });

    test('handles a moov box placed before mdat data (leading moov)', () {
      final bytes = _mp4(timescale: 600, duration: 3600); // 6 s clip
      final seconds = mp4DurationSeconds(bytes);
      expect(seconds, closeTo(6.0, 0.001));
    });

    test('returns null for garbage / non-MP4 payloads — never throws', () {
      expect(mp4DurationSeconds(Uint8List(0)), isNull);
      expect(mp4DurationSeconds(Uint8List.fromList(List.filled(64, 0xFF))),
          isNull);
      expect(
          mp4DurationSeconds(
              Uint8List.fromList('not a video at all'.codeUnits)),
          isNull);
    });

    test('returns null for a truncated box (declared size > data)', () {
      final bytes = _mp4(timescale: 1000, duration: 90000);
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 12);
      // The moov box now claims more bytes than exist — parser must bail.
      final seconds = mp4DurationSeconds(Uint8List.fromList(truncated));
      expect(seconds, isNull);
    });
  });

  group('poster object naming', () {
    test('poster name derives deterministically from the clip object name',
        () {
      expect(MediaUploadService.posterObjectNameFor('uid/123.mp4'),
          'uid/123.mp4.jpg');
      // The same name is used by the live upload and the outbox replay, so
      // a replayed publish overwrites (upsert) instead of duplicating.
      expect(MediaUploadService.posterObjectNameFor('uid/123.mp4'),
          MediaUploadService.posterObjectNameFor('uid/123.mp4'));
    });
  });
}
