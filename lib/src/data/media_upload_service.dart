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
    this.previewBytes,
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

  /// Decoded image bytes for the composer's visual preview card — the
  /// picked image itself, or a poster frame grabbed from the video. Null
  /// when no preview could be produced (VM video probe, demo mode); the
  /// UI then falls back to an icon placeholder. Never persisted — the feed
  /// renders the uploaded CDN URL instead.
  final Uint8List? previewBytes;
}

/// A media file the user picked, validated and read — everything needed
/// for the composer's visual preview and the subsequent storage upload.
class PickedMedia {
  const PickedMedia({
    required this.file,
    required this.bytes,
    required this.isVideo,
    required this.durationSeconds,
    required this.previewBytes,
  });

  /// The platform file handle (name, extension, size).
  final PlatformFile file;

  /// The full file payload to push to Supabase Storage.
  final Uint8List bytes;

  /// True for device video, false for device photo.
  final bool isVideo;

  /// Video length in seconds (≤ 180), from the web duration probe. Null
  /// for images and on VM builds (the IO size guard applies instead).
  final int? durationSeconds;

  /// Decoded image bytes for the composer's preview card — the picked
  /// image, or a poster frame from the video. Null when none was captured.
  final Uint8List? previewBytes;
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
///   is probed exactly from the file blob before upload and a poster frame
///   is captured for the preview; on IO builds an additional 200 MB size
///   guard applies (long videos are too big).
/// * Images: jpg/png/webp up to 10 MB.
/// * Offline/demo mode: no storage backend — the caller posts caption-only.
///
/// Every failure path throws [MediaUploadException] with an actionable,
/// user-facing reason — never a bare transport dump and never a silent
/// fallthrough to a caption-only post.
class MediaUploadService {
  MediaUploadService._();
  static final MediaUploadService instance = MediaUploadService._();

  static const _bucket = 'feed-media';
  static const _maxImageBytes = 10 * 1024 * 1024;
  static const _maxIoVideoBytes = 200 * 1024 * 1024;

  /// Hard deadline for one storage round-trip. A hung upload must fail
  /// with a clear message instead of spinning the composer forever.
  static const _uploadTimeout = Duration(seconds: 60);

  /// Opens the device picker, applies the validation rules and uploads.
  /// Returns null only when the user cancels the picker or demo mode is
  /// active; every failure surfaces as [MediaUploadException].
  Future<MediaUploadResult?> pickAndUpload({bool video = true}) async {
    final picked = await pick(video: video);
    if (picked == null) return null;
    return upload(picked);
  }

  /// Stage 1 of the upload flow: opens the device picker, applies the
  /// validation rules, reads the bytes and captures a preview image for
  /// the composer's visual card. The upload has NOT happened yet.
  ///
  /// Returns null when the user cancels the picker, or in demo mode (no
  /// storage backend to upload to — the caller posts caption-only, so the
  /// picker is not even opened); every failure surfaces as
  /// [MediaUploadException].
  Future<PickedMedia?> pick({bool video = true}) async {
    if (!SupabaseConfig.available) {
      // Demo mode: keep the post local-only (no storage backend).
      debugPrint('[Media] demo mode — skipping media pick');
      return null;
    }
    final List<PlatformFile> pickedFiles;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: video ? FileType.video : FileType.image,
        // Web must hold the bytes (probe + upload); IO streams from the path.
        withData: kIsWeb,
      );
      pickedFiles = picked?.files ?? const <PlatformFile>[];
    } catch (e) {
      // e.g. MissingPluginException in a wrapper webview — the picker is
      // unavailable, which previously fell through as a silent cancel.
      debugPrint('[Media] picker failed: $e');
      throw MediaUploadException(
        'The file picker is unavailable on this device/browser — paste a '
        'video or image link instead.',
      );
    }
    final file = pickedFiles.isEmpty ? null : pickedFiles.first;
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

    Uint8List? bytes;
    try {
      bytes = await readFileBytes(file);
    } catch (e) {
      debugPrint('[Media] reading "${file.name}" failed: $e');
      throw MediaUploadException(
          'Could not read "${file.name}" — the file may have moved. '
          'Pick it again.');
    }
    if (bytes == null) {
      throw MediaUploadException(
          'Could not read "${file.name}" (${(file.size / (1024 * 1024))
                  .toStringAsFixed(1)} MB) — the file may have moved. '
          'Pick it again.');
    }

    // Visual preview for the composer card: the image itself, or a poster
    // frame probed off the video blob (null → UI shows a video placeholder).
    Uint8List? previewBytes;
    double? probed;
    if (video && kIsWeb) {
      final probe = await probeWebVideo(file);
      probed = probe.durationSeconds;
      previewBytes = probe.frameBytes;
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
    } else if (!video) {
      previewBytes = bytes;
    }

    return PickedMedia(
      file: file,
      bytes: bytes,
      isVideo: video,
      durationSeconds: probed?.ceil(),
      previewBytes: previewBytes,
    );
  }

  /// Stage 2 of the upload flow: pushes a previously [pick]ed media file to
  /// Supabase Storage and returns the CDN URL the feed card renders.
  ///
  /// Throws [MediaUploadException] on every failure path with an actionable
  /// user-facing reason.
  Future<MediaUploadResult> upload(PickedMedia media) async {
    final bytes = media.bytes;
    final file = media.file;
    final video = media.isVideo;
    final probedSeconds = media.durationSeconds?.toDouble();
    final previewBytes = media.previewBytes;

    final client = SupabaseConfig.client;
    final ext = (file.extension ?? (video ? 'mp4' : 'jpg')).toLowerCase();
    final uid = client.auth.currentUser?.id ?? 'anon';
    final objectName = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      await client.storage.from(_bucket).uploadBinary(
            objectName,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          ).timeout(_uploadTimeout, onTimeout: () {
        throw MediaUploadException(
          'The upload took too long — check your connection (or switch to '
          'Wi-Fi) and try a shorter clip.',
        );
      });
    } on MediaUploadException {
      rethrow; // Timeout above already carries an actionable message.
    } on StorageException catch (e) {
      throw MediaUploadException(
          _storageFailureMessage(e, file.size));
    } catch (e) {
      // Transport-level failure (SocketException, ClientException, …) —
      // previously this escaped as a bare dump or vanished silently.
      debugPrint('[Media] upload of "$objectName" failed: $e');
      throw MediaUploadException(
        'Upload failed — the server could not be reached. Check your '
        'connection and try again; the post text is kept.',
      );
    }

    return MediaUploadResult(
      publicUrl: client.storage.from(_bucket).getPublicUrl(objectName),
      platform: video ? 'radar-video' : 'radar-image',
      mediaKind: video ? 'device_video' : 'device_photo',
      durationSeconds: video ? probedSeconds?.ceil() : null,
      previewBytes: previewBytes,
    );
  }

  /// Maps a Supabase Storage failure to a specific, actionable message —
  /// never a bare "Upload failed: status" dump. Exposed for tests.
  @visibleForTesting
  static String storageFailureMessage(StorageException e, int fileSizeBytes) =>
      instance._storageFailureMessage(e, fileSizeBytes);

  String _storageFailureMessage(StorageException e, int fileSizeBytes) {
    // storage_client surfaces the HTTP status as a string (or null when
    // the request never got a response — i.e. offline / stalled).
    final status = int.tryParse(e.statusCode ?? '') ?? 0;
    if (status == 413) {
      return 'That file is too large for the server '
              '(${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB) — '
              'use a shorter clip or smaller image.';
    }
    if (status == 403) {
      return 'Upload rejected: the media storage rules denied it. Your '
              'session may have expired — reopen the app and try again.';
    }
    if (status == 409 || e.message.toLowerCase().contains('exists')) {
      return 'An upload with that name already exists — wait a second and '
              'try again.';
    }
    if (status == 0) {
      return 'Upload failed — the media server could not be reached. Check '
              'your connection and try again.';
    }
    return 'Upload failed (${e.statusCode ?? 'unknown status'}): '
        '${e.message}';
  }
}
