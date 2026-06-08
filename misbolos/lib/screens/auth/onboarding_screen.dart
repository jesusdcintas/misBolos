import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/auth_controller.dart';

const onboardingSeenKey = 'onboarding_seen_v1';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.status == AuthStatus.loading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 420),
                tween: Tween(begin: 0, end: 1),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 24 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CloudArtwork(),
                    const SizedBox(height: 24),
                    Text(
                      'Usa MisBolos en todos tus dispositivos',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sincroniza automáticamente bolos, clientes y facturas con tu cuenta Google.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: loading
                          ? null
                          : () => _continueWithGoogle(context, ref),
                      child: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continuar con Google'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _skip(context),
                      child: const Text('Ahora no'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _continueWithGoogle(BuildContext context, WidgetRef ref) async {
    final ok = await ref
        .read(authControllerProvider.notifier)
        .signInWithGoogle();
    if (!context.mounted) return;
    if (ok) {
      await _markSeen();
      if (context.mounted) context.go('/');
    }
  }

  Future<void> _skip(BuildContext context) async {
    await _markSeen();
    if (context.mounted) context.go('/login');
  }

  Future<void> _markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingSeenKey, true);
  }
}

class _CloudArtwork extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withValues(alpha: 0.85),
            cs.surfaceContainerHighest.withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 30,
            child: Icon(Icons.cloud_outlined, size: 56, color: cs.primary),
          ),
          Positioned(
            bottom: 28,
            left: 72,
            child: _DeviceRect(width: 68, height: 48),
          ),
          Positioned(
            bottom: 22,
            right: 76,
            child: _DeviceRect(width: 44, height: 64),
          ),
        ],
      ),
    );
  }
}

class _DeviceRect extends StatelessWidget {
  final double width;
  final double height;

  const _DeviceRect({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
        color: cs.surface,
      ),
    );
  }
}
