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
    required this.sandbox,
    this.scopes = defaultScopes,
  });

  /// Pi Apps SDK version passed to `Pi.init({ version })`.
  final String sdkVersion;

  /// Master switch. When false the UI offers the demo fallback login.
  final bool enabled;

  /// Testnet sandbox mode. While the app is being polished all payments
  /// settle on **Pi Testnet** (the SDK's sandbox flag) — flip to false for
  /// the Mainnet launch once the app is fully verified.
  ///
  /// Build with:
  ///   --dart-define=PI_SANDBOX=false   (Mainnet / production)
  ///   (default: true — Testnet)
  final bool sandbox;

  /// Scopes requested during `Pi.authenticate`.
  final List<String> scopes;

  static const List<String> defaultScopes = <String>[
    'username',
    'payments',
  ];

  /// The app's Pi environment. Plain browsers without `window.Pi` fall back
  /// to demo mode at runtime.
  static final PiConfig current = PiConfig(
    sdkVersion: '2.0',
    enabled: true,
    sandbox: const bool.fromEnvironment('PI_SANDBOX', defaultValue: true),
  );
}
