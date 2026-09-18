// Web composition root for the Pi SDK.
//
// This file is selected by the conditional import in `pi_sdk_bridge.dart`
// when `dart.library.js_interop` is available (Flutter Web).
library;

import 'pi_sdk_api.dart';
import 'pi_sdk_js.dart';

/// The platform implementation used by [piSdk].
final PiSdkApi piSdk = PiSdkWeb();
