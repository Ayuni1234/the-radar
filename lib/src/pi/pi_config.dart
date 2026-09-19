/// Runtime configuration for the Pi Network integration.
///
/// Sandbox/testnet is the default: `Pi.init({ version: '2.0', sandbox: true })`
/// runs against sandbox.minepi.com so test transactions never touch real Pi.
/// Override per build with `--dart-define=PI_SANDBOX=false` for mainnet.
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
  /// (Kept for explicitness; runtime detection makes it equivalent to the
  /// sandbox preset outside the Pi Browser.)
  static const PiConfig local = PiConfig(
    sdkVersion: '2.0',
    sandbox: true,
    enabled: false,
  );

  /// Compile-time environment switch, e.g.
  /// `--dart-define=PI_SANDBOX=true` (testnet, default) or
  /// `--dart-define=PI_SANDBOX=false` (mainnet, Pi Browser production).
  static const bool _kEnvSandbox =
      bool.fromEnvironment('PI_SANDBOX', defaultValue: true);

  /// Environment resolved at startup. Defaults to sandbox/testnet; plain
  /// browsers (no Pi Browser) still fall back to demo mode at runtime.
  static PiConfig current = _kEnvSandbox ? sandboxEnv : prod;
}
