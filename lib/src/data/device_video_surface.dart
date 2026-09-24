import 'package:flutter/widgets.dart';

import 'device_video_surface_stub.dart'
    if (dart.library.js_interop) 'device_video_surface_web.dart' as impl;

/// Everything the platform video surface needs to render a device-uploaded
/// clip inside the feed hero.
class DeviceVideoSurfaceSpec {
  const DeviceVideoSurfaceSpec({
    required this.url,
    this.posterUrl,
    this.durationSeconds,
  });

  /// Public CDN URL of the clip (`feed_posts.media_url`).
  final String url;

  /// Public CDN URL of the persisted poster frame
  /// (`feed_posts.media_poster_url`) — shows instantly while the video
  /// buffers, and is the whole hero on platforms without a video element.
  final String? posterUrl;

  /// Clip length in seconds (≤ 180) for the duration chip.
  final int? durationSeconds;
}

/// Image treatment for platforms without an embedded video element (and for
/// clips still buffering on web): the poster frame fills the hero canvas.
Widget posterImage(DeviceVideoSurfaceSpec spec) {
  if (spec.posterUrl == null || spec.posterUrl!.isEmpty) {
    return const SizedBox.shrink();
  }
  return Image.network(
    spec.posterUrl!,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
    loadingBuilder: (context, child, progress) =>
        progress == null ? child : const SizedBox.shrink(),
  );
}

/// Renders a device video for the current platform:
/// * web — a real `<video>` element (controls, muted loop, poster);
/// * IO — the persisted poster frame as a static image.
Widget deviceVideoSurface(DeviceVideoSurfaceSpec spec) =>
    impl.deviceVideoSurface(spec);
