// Conditional-import bridge for the Pi SDK.
//
// Usage: `import 'pi_sdk_bridge.dart' show piSdk;`
//
// On Flutter Web this resolves to the real dart:js_interop implementation in
// `pi_sdk_js.dart`; on VM/test platforms it resolves to `pi_sdk_stub.dart`
// so the app compiles and runs headlessly (demo mode).
library;

export 'pi_sdk_stub.dart' if (dart.library.js_interop) 'pi_sdk_web.dart';
