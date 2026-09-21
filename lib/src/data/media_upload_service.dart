import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import 'media_duration_probe.dart';
import 'read_file_bytes.dart';

/// The strict highlight-reel cap: videos longer than this are rejected so
/// scouts can review concise clips before committing to a live session.
const Duration maxVideoDuration = Duration(minutes: 3);

/// Outcome of a successful media pick + upload.
class MediaUploadResult {
  const MediaUploadResult({
    required this.publicUrl,
    required this.platform,
    required this.mediaKind,
    this.durationSeconds,
  });

  /// Public CDN URL stored into `feed_posts.media_url`.
  final String publicUrl;

  /// Storage tag persisted into `feed_posts.media_platform`
  /// ('radar-video' / 'radar-image').
  final String platform;

  /// Persisted into `feed_posts.media_kind`
  /// ('device_video' / 'device_photo').
  final String mediaKind;

  /// Video length in seconds (≤ 180). Null for images.
  final int? durationSeconds;
}

/// Exception carrying a user-facing reason (e.g. the 3-minute rule).
class MediaUploadException implements Exception {
  MediaUploadException(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Device media uploads → Supabase Storage (`feed-media` bucket, public).
///
/// * Video: hard [maxVideoDuration] limit of 3 minutes. On web the duration
///   is probed exactly from the file blob before upload; on IO builds an
///   additional 200 MB size guard applies (long videos are too big).
/// * Images: jpg/png/webp up to 10 MB.
/// * Offline/demo mode: no storage backend — the caller posts caption-only.
class MediaUploadService {
  MediaUploadService._();
  static final MediaUploadService instance = MediaUploadService._();

  static const _bucket = 'feed-media';
  static const _maxImageBytes = 10 * 1024 * 1024;
  static const _maxIoVideoBytes = 200 * 1024 * 1024;

  /// Opens the device picker, applies the validation rules and uploads.
  /// Returns null when the user cancels or Supabase isn't available.
  Future<MediaUploadResult?> pickAndUpload({bool video = true}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: video ? FileType.video : FileType.image,
      // Web must hold the bytes (probe + upload); IO streams from the path.
      withData: kIsWeb,
    );
    final file = picked?.files.single;
    if (file == null) return null; // User cancelled.

    if (video) {
      if (kIsWeb) {
        // Duration is validated during the byte-read step below (single
        // probe shared between validation and metadata).
      } else if (file.size > _maxIoVideoBytes) {
        // Mobile/desktop fallback: 200 MB at typical phone bitrates ≈ >3 min.
        throw MediaUploadException(
          'That video is too large — keep highlight reels to '
          '${maxVideoDuration.inMinutes} minutes or less.',
        );
      }
    } else {
      if (file.size > _maxImageBytes) {
        throw MediaUploadException('Images must be under 10 MB.');
      }
    }

    if (!SupabaseConfig.available) {
      // Demo mode: keep the post local-only (no storage backend).
      debugPrint('[Media] demo mode — skipping upload of "${file.name}"');
      return null;
    }

    final bytes = await readFileBytes(file);
    if (bytes == null) {
      throw MediaUploadException('Could not read the selected file.');
    }
    double? probed;
    if (video && kIsWeb) {
      probed = await probeWebVideoSeconds(file);
      if (probed == null) {
        throw MediaUploadException(
            'Could not read the video length — please pick it again.');
      }
      if (probed > maxVideoDuration.inSeconds) {
        throw MediaUploadException(
          'Videos must be ${maxVideoDuration.inMinutes} minutes or shorter '
          '— scouts review quick highlights first. This clip is '
          '${(probed / 60).toStringAsFixed(1)} min.',
        );
      }
    }
    return _uploadBytes(bytes, file, video, probed);
  }

  Future<MediaUploadResult> _uploadBytes(
    Uint8List bytes,
    PlatformFile file,
    bool video,
    double? probedSeconds,
  ) async {
    final client = SupabaseConfig.client;
    final ext = (file.extension ?? (video ? 'mp4' : 'jpg')).toLowerCase();
    final uid = client.auth.currentUser?.id ?? 'anon';
    final objectName = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      await client.storage.from(_bucket).uploadBinary(
            objectName,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );
    } on StorageException catch (e) {
      throw MediaUploadException('Upload failed: ${e.message}');
    }

    return MediaUploadResult(
      publicUrl: client.storage.from(_bucket).getPublicUrl(objectName),
      platform: video ? 'radar-video' : 'radar-image',
      mediaKind: video ? 'device_video' : 'device_photo',
      // The duration check already capped this at maxVideoDuration.
      durationSeconds: video ? probedSeconds?.ceil() : null,
    );
  }
}
