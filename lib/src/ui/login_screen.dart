import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pi/pi_config.dart';
import '../state/auth_controller.dart';
import 'radar_theme.dart';
import 'shell.dart';

/// Sign-in entry: Pi Network authentication with a demo fallback.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final pi = ref.read(authProvider.notifier).pi;
    final sdkAvailable = pi?.isSdkAvailable ?? false;

    Widget body;
    final state = auth.value;
    if (state is AuthLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state is AuthError) {
      body = _ErrorCard(message: state.message);
    } else if (state is AuthSignedOut && state.reason != null) {
      body = _ErrorCard(message: state.reason!);
    } else {
      body = const SizedBox.shrink();
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.9),
            radius: 1.4,
            colors: [Color(0xFF14203A), RadarTheme.ink],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(child: RadarMark(size: 72)),
                    const SizedBox(height: 20),
                    Text(
                      'THE RADAR',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 6,
                              ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Global Football Scouting Platform',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: RadarTheme.textDim),
                    ),
                    const SizedBox(height: 36),
                    _PiSignInCard(
                      sdkAvailable: sdkAvailable,
                      enabled: PiConfig.current.enabled,
                      busy: state is AuthLoading,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          state is AuthLoading ? null : () => ref.read(authProvider.notifier).signInDemo(),
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text('Explore demo mode'),
                    ),
                    const SizedBox(height: 18),
                    if (body != const SizedBox.shrink()) body,
                    const SizedBox(height: 26),
                    const _EnvFootnote(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PiSignInCard extends ConsumerWidget {
  const _PiSignInCard({
    required this.sdkAvailable,
    required this.enabled,
    required this.busy,
  });

  final bool sdkAvailable;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canPi = sdkAvailable && enabled;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: RadarTheme.pi.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.currency_exchange,
                    color: RadarTheme.pi, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Sign in with Pi Network',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            canPi
                ? 'Authenticate with your Pi account. We capture your Pi UID, username and KYC verification status.'
                : sdkAvailable
                    ? 'Pi SDK detected but Pi logins are disabled in this build config.'
                    : 'Pi SDK not detected — open The Radar inside the Pi Browser for full sign-in, or explore demo mode.',
            style: const TextStyle(color: RadarTheme.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: canPi
                ? FilledButton.styleFrom(
                    backgroundColor: RadarTheme.pi,
                    foregroundColor: Colors.white,
                  )
                : FilledButton.styleFrom(
                    backgroundColor: RadarTheme.panelHigh,
                    foregroundColor: RadarTheme.textDim,
                  ),
            onPressed: canPi && !busy
                ? () => ref.read(authProvider.notifier).signInWithPi()
                : null,
            icon: const Icon(Icons.login, size: 18),
            label: Text(busy ? 'Authenticating…' : 'Continue with Pi'),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.alert.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.alert.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: RadarTheme.alert, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, color: RadarTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnvFootnote extends ConsumerWidget {
  const _EnvFootnote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pi = ref.read(authProvider.notifier).pi;
    final env = 'Pi SDK v${PiConfig.current.sdkVersion}';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (pi?.isSdkAvailable ?? false)
                ? RadarTheme.radar
                : RadarTheme.gold,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          (pi?.isSdkAvailable ?? false)
              ? 'Pi SDK ready · $env'
              : 'Pi SDK absent · demo environment',
          style: const TextStyle(fontSize: 11.5, color: RadarTheme.textDim),
        ),
      ],
    );
  }
}
