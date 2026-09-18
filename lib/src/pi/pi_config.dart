/// Runtime configuration for the Pi Network integration.
///
/// `PiConfig.local` is the default so that `flutter run` in a plain browser
/// never fires real Pi dialogs; flip to `PiConfig.mainnet` when deploying
/// behind the Pi Browser, or `PiConfig.sandbox` for sandbox testing.
class PiConfig {
  const PiConfig({
    required this.sdkVersion,
    required this.sandbox,
    required this.enabled,
    this.scopes = defaultScopes,
  });

  /// Pi Apps SDK version passed to `Pi.init({ version })`.
  final String sdkVersion;

  /// `true` → `Pi.init({ sandbox: true })`, requires sandbox.minepi.com host.
  final bool sandbox;

  /// Master switch. When false the UI offers the demo fallback login.
  final bool enabled;

  /// Scopes requested during `Pi.authenticate`.
  final List<String> scopes;

  static const List<String> defaultScopes = <String>[
    'username',
    'payments',
  ];

  /// Live Pi Browser environment.
  static const PiConfig prod = PiConfig(
    sdkVersion: '2.0',
    sandbox: false,
    enabled: true,
  );

  /// Kept as an alias for readability at call sites.
  static const PiConfig mainnet = PiConfig.prod;

  /// Sandbox environment (sandbox.minepi.com).
  static const PiConfig sandboxEnv = PiConfig(
    sdkVersion: '2.0',
    sandbox: true,
    enabled: true,
  );

  /// Plain-browser development: Pi SDK absent, demo mode available.
  static const PiConfig local = PiConfig(
    sdkVersion: '2.0',
    sandbox: false,
    enabled: false,
  );

  /// Environment chosen at startup.
  static PiConfig current = PiConfig.local;
}
