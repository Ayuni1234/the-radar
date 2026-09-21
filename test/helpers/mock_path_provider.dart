import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_map 8's built-in tile cache probes path_provider on IO; widget
/// tests have no plugin platform, so answer the channel with a temp dir.
/// Call once from `main()` in any test suite that pumps the Radar map.
void mockPathProviderForMapCache() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => Directory.systemTemp.createTempSync('radar_map_cache').path,
  );
}
