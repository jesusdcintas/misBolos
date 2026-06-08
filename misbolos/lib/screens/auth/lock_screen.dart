import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/app_lock_manager.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.manager});

  final AppLockManager manager;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();

  late final AnimationController _introController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  late final AnimationController _shakeController;
  late final Animation<double> _shake;

  bool _showPin = false;
  bool _autoBiometricAttempted = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _introController, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic),
    );

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shake = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
        TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
        TweenSequenceItem(tween: Tween(begin: 10, end: -8), weight: 2),
        TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 2),
        TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 2),
      ],
    ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

    _introController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 380), () {
        if (!mounted || _autoBiometricAttempted) return;
        _autoBiometricAttempted = true;
        _handleBiometric();
      });
    });
  }

  Future<void> _handleBiometric() async {
    if (!widget.manager.canUseBiometric) return;
    setState(() => _message = null);

    final result = await widget.manager.unlockWithBiometrics();
    if (!mounted) return;

    if (result == BiometricUnlockResult.success) {
      await HapticFeedback.lightImpact();
      return;
    }

    setState(() {
      _message = switch (result) {
        BiometricUnlockResult.unavailable =>
          'Biometría no disponible en este dispositivo.',
        BiometricUnlockResult.cancelled =>
          'Autenticación cancelada. Puedes reintentar.',
        BiometricUnlockResult.error => 'No se pudo validar la biometría.',
        BiometricUnlockResult.failed => 'No se pudo validar la biometría.',
        BiometricUnlockResult.success => null,
      };
    });
  }

  Future<void> _submitPin() async {
    final ok = widget.manager.validatePin(_pinController.text);
    if (ok) {
      await HapticFeedback.lightImpact();
      return;
    }

    setState(() => _message = 'PIN incorrecto. Inténtalo de nuevo.');
    unawaited(_shakeController.forward(from: 0));
    await HapticFeedback.vibrate();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _introController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final biometricLabel = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'Desbloquear con Touch ID',
      TargetPlatform.iOS => 'Desbloquear con Face ID',
      _ => 'Desbloquear con biometría',
    };
    final biometricIcon = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => Icons.fingerprint_rounded,
      TargetPlatform.iOS => Icons.face_rounded,
      _ => Icons.fingerprint_rounded,
    };

    final bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              const Color(0xFF0E111A),
              const Color(0xFF12192A),
              const Color(0xFF0D1321),
            ]
          : [
              const Color(0xFFF4F8FF),
              const Color(0xFFEFF4FF),
              const Color(0xFFE8EEFF),
            ],
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(_shake.value, 0),
                      child: child,
                    );
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Card(
                      elevation: 0,
                      color: colorScheme.surface.withValues(
                        alpha: isDark ? 0.88 : 0.94,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.18),
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.14,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.lock_rounded,
                                color: colorScheme.primary,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'MisBolos',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'MisBolos está bloqueado',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Desbloquea para continuar',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            if (_message != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _message!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            if (widget.manager.canUseBiometric)
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: widget.manager.isUnlocking
                                      ? null
                                      : _handleBiometric,
                                  icon: Icon(biometricIcon),
                                  label: Text(
                                    widget.manager.isUnlocking
                                        ? 'Verificando...'
                                        : biometricLabel,
                                  ),
                                ),
                              ),
                            if (widget.manager.canUsePin) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () =>
                                      setState(() => _showPin = !_showPin),
                                  child: const Text('Usar PIN'),
                                ),
                              ),
                            ],
                            if (_showPin && widget.manager.canUsePin) ...[
                              const SizedBox(height: 14),
                              TextField(
                                controller: _pinController,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                obscureText: true,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submitPin(),
                                decoration: const InputDecoration(
                                  labelText: 'PIN',
                                  hintText: '4-8 dígitos',
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _submitPin,
                                  child: const Text('Desbloquear'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
