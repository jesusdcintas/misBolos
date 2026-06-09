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
    final ink = cs.onSurface;
    final accent = cs.primary;
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
            top: 26,
            child: Container(
              width: 74,
              height: 48,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: ink.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(Icons.cloud_done_outlined, size: 34, color: accent),
            ),
          ),
          Positioned(bottom: 24, left: 44, child: _MacDevice()),
          Positioned(bottom: 20, right: 54, child: _IphoneDevice()),
        ],
      ),
    );
  }
}

class _MacDevice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = cs.onSurface;
    return SizedBox(
      width: 138,
      height: 74,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 124,
              height: 64,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ink.withValues(alpha: 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: ink.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Dot(color: cs.error),
                        const SizedBox(width: 4),
                        _Dot(color: cs.tertiary),
                        const SizedBox(width: 4),
                        _Dot(color: cs.primary),
                      ],
                    ),
                    const SizedBox(height: 9),
                    _Line(width: 54, color: cs.primary),
                    const SizedBox(height: 6),
                    _Line(width: 92, color: ink.withValues(alpha: 0.22)),
                    const SizedBox(height: 5),
                    _Line(width: 72, color: ink.withValues(alpha: 0.16)),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 138,
            height: 8,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }
}

class _IphoneDevice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = cs.onSurface;
    return Container(
      width: 58,
      height: 92,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 7),
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: ink.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 4,
              child: Container(
                width: 18,
                height: 4,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Positioned(
              top: 20,
              child: Icon(Icons.music_note, size: 17, color: cs.primary),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 26,
              child: _Line(width: 28, color: cs.primary),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 18,
              child: _Line(width: 22, color: ink.withValues(alpha: 0.18)),
            ),
            Positioned(
              bottom: 7,
              child: Container(
                width: 18,
                height: 3,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Line extends StatelessWidget {
  final double width;
  final Color color;

  const _Line({required this.width, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
