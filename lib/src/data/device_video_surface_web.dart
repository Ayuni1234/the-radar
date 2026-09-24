import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'device_video_surface.dart' as iface;

/// The registry keeps one factory per view type for the lifetime of the
/// page, so each video URL gets exactly one cached `<video>` element —
/// rebuilt cards and re-entered screens replay the same element instead of
/// stacking up players. One cached element is a few hundred KB of metadata;
/// a feed of video posts stays well within budget.
const int _maxCachedPlayers = 12;
final Map<String, web.HTMLVideoElement> _players = {};
final Set<String> _registeredFactories = {};

/// Renders a device-uploaded video as a real `<video>` element in a
/// [HtmlElementView] — the feed hero plays the actual clip, with the
/// persisted poster frame showing instantly while the video buffers.
Widget deviceVideoSurface(iface.DeviceVideoSurfaceSpec spec) {
  // Registry view-type keys must be plain tokens — derive a stable,
  // collision-free-enough key from the URL itself.
  final viewType =
      'radar-device-video-${spec.url.hashCode.toRadixString(36)}';
  if (_registeredFactories.add(viewType)) {
    final poster = spec.posterUrl ?? '';
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final player = _videoFor(spec.url, poster);
      player.id = 'radar-video-$viewId';
      return player;
    });
  }
  return HtmlElementView(viewType: viewType);
}

web.HTMLVideoElement _videoFor(String url, String poster) {
  final existing = _players[url];
  if (existing != null) return existing;

  final video = web.HTMLVideoElement();
  video.src = url;
  video.muted = true; // autoplay policies — silent looped preview
  video.loop = true;
  video.playsInline = true;
  video.setAttribute('playsinline', '');
  video.setAttribute('controls', 'true');
  video.style.width = '100%';
  video.style.height = '100%';
  video.style.objectFit = 'cover';
  video.style.backgroundColor = '#000000';
  if (poster.isNotEmpty) video.poster = poster;
  _players[url] = video;
  // Trim oldest entries when the cache outgrows its budget.
  while (_players.length > _maxCachedPlayers) {
    _players.remove(_players.keys.first);
  }
  return video;
}

/// Warm-up hook for future prefetch — no-op semantics on web.
Future<void> prewarmDeviceVideo(String url) async {}

/// Debug counter (exposed for tests).
int get cachedVideoPlayerCount => _players.length;
