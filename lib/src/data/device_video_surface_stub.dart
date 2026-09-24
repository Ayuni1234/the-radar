import 'package:flutter/widgets.dart';

import 'device_video_surface.dart' as iface;

/// IO builds (and any platform without a DOM): there is no `<video>`
/// element to embed, so the surface renders the persisted poster frame as
/// the hero — the native in-app video player is a platform-channel feature
/// outside this web-first build's scope. Posterless videos keep the
/// placeholder treatment.
Widget deviceVideoSurface(iface.DeviceVideoSurfaceSpec spec) {
  return iface.posterImage(spec);
}

/// Warm-up hook — nothing to warm on IO.
Future<void> prewarmDeviceVideo(String url) async {}
