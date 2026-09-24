import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
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

/// View type for a clip URL — the single source of truth shared by the
/// registry and [_VideoHeroSurface] so both address the same slot.
String viewTypeFor(String url) =>
    'radar-device-video-${url.hashCode.toRadixString(36)}';

/// Renders a device-uploaded clip as the feed hero:
///
/// * a poster `<img>` + `<video>` stack inside the platform-view slot, so
///   the real poster frame is visible *while the video buffers* (the slot
///   is opaque — a Flutter layer underneath it would never show),
/// * the clip autoplays muted + looped (Instagram-style living preview),
/// * a tap on the clip toggles play/pause,
/// * mute (bottom-right) and native-fullscreen (bottom-left) controls.
///
/// All interactive chrome is built DOM-side, **inside** the platform-view
/// slot: on web, DOM platform views composite *above* the Flutter canvas,
/// so any Flutter widget layered over an [HtmlElementView] would be both
/// invisible (painted under the slot) and untappable.
Widget deviceVideoSurface(iface.DeviceVideoSurfaceSpec spec) {
  final video = _videoFor(spec.url, spec.posterUrl ?? '');
  final viewType = viewTypeFor(spec.url);
  if (_registeredFactories.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(
        viewType, (int viewId) => video.parentElement ?? video);
  }
  return _VideoHeroSurface(
    key: ValueKey(viewType),
    video: video,
    viewType: viewType,
  );
}

web.HTMLVideoElement _videoFor(String url, String poster) {
  final existing = _players[url];
  if (existing != null) return existing;

  final video = web.HTMLVideoElement()
    ..src = url
    ..muted = true // autoplay policies — silent looped preview
    ..loop = true
    ..autoplay = true
    ..playsInline = true;
  video.setAttribute('playsinline', '');
  video.preload = 'auto';
  if (poster.isNotEmpty) video.poster = poster;
  // Transparent until frames render — the poster <img> beneath shows
  // through while the clip buffers.
  video.style
    ..width = '100%'
    ..height = '100%'
    ..objectFit = 'cover'
    ..backgroundColor = 'transparent';

  final container = web.document.createElement('div') as web.HTMLDivElement
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.position = 'relative'
    ..style.overflow = 'hidden'
    ..style.backgroundColor = '#000000'
    ..style.cursor = 'pointer';
  if (poster.isNotEmpty) {
    final img = web.document.createElement('img') as web.HTMLImageElement
      ..src = poster
      ..alt = ''
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.position = 'absolute'
      ..style.inset = '0'
      ..style.objectFit = 'cover'
      ..style.pointerEvents = 'none';
    container.appendChild(img);
  }
  video.style.position = 'absolute';
  video.style.inset = '0';
  container.appendChild(video);

  // Tap the clip itself to play/pause — the DOM element receives the click
  // before Flutter's hit-test, so the handler must live DOM-side.
  container.onclick = (web.MouseEvent _) {
    if (video.paused) {
      video.play();
    } else {
      video.pause();
    }
  }.toJS;

  // Mute pill (bottom-right): mirrors the mute state into the icon.
  final mutePill = _chromeButton(_svgMuted, right: 10, bottom: 10);
  mutePill.onclick = (web.MouseEvent _) {
    video.muted = !video.muted;
    // Unmuting implies the user wants to hear it — start playback if the
    // clip is paused (this tap is the user gesture browsers require).
    if (!video.muted && video.paused) {
      video.play().toDart.catchError((Object _) => null);
    }
    mutePill.innerHTML = video.muted ? _svgMuted.toJS : _svgSound.toJS;
  }.toJS;
  container.appendChild(mutePill);

  // Native fullscreen (bottom-left): the fullscreen API is DOM-native, so
  // the clip renders above everything — a Flutter fullscreen route could
  // never cover the platform view on web. Native controls come along for
  // the ride and are switched off again when the overlay closes.
  final expandPill = _chromeButton(_svgExpand, left: 10, bottom: 10);
  expandPill.onclick = (web.MouseEvent _) {
    _enterNativeFullscreen(video);
  }.toJS;
  container.appendChild(expandPill);

  _players[url] = video;
  // Trim oldest entries when the cache outgrows its budget.
  while (_players.length > _maxCachedPlayers) {
    _players.remove(_players.keys.first);
  }
  return video;
}

void _enterNativeFullscreen(web.HTMLVideoElement video) {
  video.controls = true;
  try {
    video.requestFullscreen().toDart.catchError((Object _) => null);
  } catch (_) {
    // Older Safari only exposes the vendor-prefixed video API.
    try {
      video.enterFullscreenLegacy();
    } catch (_) {}
  }
  web.document.addEventListener('fullscreenchange', ((web.Event _) {
    if (web.document.fullscreenElement == null) video.controls = false;
  }).toJS);
}

extension on web.HTMLVideoElement {
  @JS('webkitEnterFullscreen')
  external void enterFullscreenLegacy();
}

/// Hides (or restores) every cached video slot. Platform views composite
/// above the Flutter canvas on web, so Flutter routes — the fullscreen
/// media viewer, modal sheets — can only cover a playing clip by hiding
/// its container DOM-side. Paused clips stay paused; muted ones resume
/// when the overlay closes.
void setDeviceVideosVisible(bool visible) {
  for (final video in _players.values) {
    final container = video.parentElement;
    if (container == null) continue;
    (container as web.HTMLElement).style.visibility =
        visible ? 'visible' : 'hidden';
    if (!visible && !video.paused) video.pause();
    if (visible && video.muted && video.paused) {
      video.play().toDart.catchError((Object _) => null);
    }
  }
}

/// Small circular control button pinned to a corner of the video slot.
web.HTMLDivElement _chromeButton(
  String svg, {
  double? left,
  double? right,
  double? bottom,
}) {
  final button = web.document.createElement('div') as web.HTMLDivElement;
  final style = button.style
    ..position = 'absolute'
    ..width = '34px'
    ..height = '34px'
    ..display = 'flex'
    ..alignItems = 'center'
    ..justifyContent = 'center'
    ..borderRadius = '999px'
    ..backgroundColor = 'rgba(0,0,0,0.72)'
    ..border = '1px solid rgba(255,255,255,0.25)'
    ..cursor = 'pointer'
    ..userSelect = 'none'
    ..zIndex = '2';
  if (left != null) style.left = '${left}px';
  if (right != null) style.right = '${right}px';
  if (bottom != null) style.bottom = '${bottom}px';
  button.innerHTML = svg.toJS;
  return button;
}

const String _svgMuted =
    '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" '
    'stroke="#ffffff" stroke-width="2" stroke-linecap="round" '
    'stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 '
    '11 19 11 5" fill="#ffffff" stroke="none"></polygon><line x1="23" '
    'y1="9" x2="17" y2="15"></line><line x1="17" y1="9" x2="23" '
    'y2="15"></line></svg>';

const String _svgSound =
    '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" '
    'stroke="#ffffff" stroke-width="2" stroke-linecap="round" '
    'stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 '
    '11 19 11 5" fill="#ffffff" stroke="none"></polygon><path d="M15.54 '
    '8.46a5 5 0 0 1 0 7.07"></path><path d="M19.07 4.93a10 10 0 0 1 0 '
    '14.14"></path></svg>';

const String _svgExpand =
    '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" '
    'stroke="#ffffff" stroke-width="2" stroke-linecap="round" '
    'stroke-linejoin="round"><path d="M4 9V4h5"></path><path d="M15 '
    '4h5v5"></path><path d="M20 15v5h-5"></path><path d="M9 20H4v-5">'
    '</path></svg>';

/// Thin Flutter wrapper over the cached platform view. All chrome lives in
/// the DOM (see [deviceVideoSurface]); this just hosts the slot.
class _VideoHeroSurface extends StatelessWidget {
  const _VideoHeroSurface({
    super.key,
    required this.video,
    required this.viewType,
  });

  final web.HTMLVideoElement video;
  final String viewType;

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: viewType);
  }
}

/// Warm-up hook for future prefetch — no-op semantics on web.
Future<void> prewarmDeviceVideo(String url) async {}

/// Debug counter (exposed for tests).
int get cachedVideoPlayerCount => _players.length;
