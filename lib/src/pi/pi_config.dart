/// Runtime configuration for the Pi Network integration.
///
/// Initialisation follows the official v2.0 standard:
/// `Pi.init({ version: "2.0" })` — no sandbox parameter. The SDK determines
/// the environment from where the app runs (the Pi Developer Portal decides
/// which registered URL is a sandbox development URL), and each payment's
/// actual network is reported in `PaymentDTO.network` ("PiTestnet" or
/// "PiMainnet").
class PiConfig {
  const PiConfig({
    required this.sdkVersion,
    required this.enabled,
    this.scopes = defaultScopes,
  });

  /// Pi Apps SDK version passed to `Pi.init({ version })`.
  final String sdkVersion;

  /// Master switch. When false the UI offers the demo fallback login.
  final bool enabled;

  /// Scopes requested during `Pi.authenticate`.
  final List<String> scopes;

  static const List<String> defaultScopes = <String>[
    'username',
    'payments',
  ];

  /// The app's Pi environment. The SDK's `sandbox` init flag is intentionally
  /// absent (official v2.0 standard); plain browsers without `window.Pi`
  /// fall back to demo mode at runtime.
  static const PiConfig current = PiConfig(
    sdkVersion: '2.0',
    enabled: true,
  );
}
