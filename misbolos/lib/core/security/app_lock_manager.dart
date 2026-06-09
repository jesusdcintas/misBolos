import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum BiometricUnlockResult { success, failed, cancelled, unavailable, error }

class AppLockManager extends ChangeNotifier {
  AppLockManager({
    LocalAuthentication? localAuth,
    Duration lockAfterBackground = const Duration(seconds: 5),
  }) : _localAuth = localAuth ?? LocalAuthentication(),
       _lockAfterBackground = lockAfterBackground;

  final LocalAuthentication _localAuth;
  Duration _lockAfterBackground;

  bool _pinEnabled = false;
  String _pinCode = '';
  bool _biometricEnabled = false;

  bool _isLocked = false;
  bool _isUnlocking = false;
  bool _unlockedForForeground = false;
  DateTime? _pausedAt;

  bool get isLocked => _isLocked;
  bool get isUnlocking => _isUnlocking;
  bool get canUsePin => _pinEnabled && _pinCode.isNotEmpty;
  bool get canUseBiometric => _biometricEnabled;
  bool get isSecurityEnabled => canUsePin || canUseBiometric;

  void updateSettings({
    required bool pinEnabled,
    required String pinCode,
    required bool biometricEnabled,
    Duration? lockAfterBackground,
  }) {
    final cleanPin = pinCode.trim();
    final changed =
        _pinEnabled != pinEnabled ||
        _pinCode != cleanPin ||
        _biometricEnabled != biometricEnabled;

    _pinEnabled = pinEnabled;
    _pinCode = cleanPin;
    _biometricEnabled = biometricEnabled;

    if (lockAfterBackground != null) {
      _lockAfterBackground = lockAfterBackground;
    }

    if (!isSecurityEnabled) {
      _unlockedForForeground = true;
      _setLocked(false);
      return;
    }

    if (changed) {
      _unlockedForForeground = false;
      _setLocked(true);
    }
  }

  void onAuthStateChanged(AuthState authState) {
    if (authState.session == null) {
      _unlockedForForeground = false;
      _setLocked(false);
      return;
    }
    _applyForegroundLockIfNeeded();
  }

  void onLifecycleChanged(AppLifecycleState state) {
    if (!isSecurityEnabled) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
      // Solo marcamos tiempo de salida. El relock se decide al volver.
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // En iOS/macOS puede saltar en transiciones internas; no forzamos lock aquí.
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    final pausedAt = _pausedAt;
    if (pausedAt == null) {
      _applyForegroundLockIfNeeded();
      return;
    }

    final elapsed = DateTime.now().difference(pausedAt);
    if (elapsed >= _lockAfterBackground) {
      _unlockedForForeground = false;
    }
    _applyForegroundLockIfNeeded();
  }

  void markUnlocked() {
    _unlockedForForeground = true;
    _setLocked(false);
  }

  bool validatePin(String rawPin) {
    final ok = rawPin.trim() == _pinCode && canUsePin;
    if (ok) {
      markUnlocked();
    }
    return ok;
  }

  Future<BiometricUnlockResult> unlockWithBiometrics() async {
    if (!canUseBiometric) return BiometricUnlockResult.unavailable;
    if (_isUnlocking) return BiometricUnlockResult.cancelled;

    _isUnlocking = true;
    notifyListeners();

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      if (!canCheck || !supported) {
        return BiometricUnlockResult.unavailable;
      }

      final success = await _localAuth.authenticate(
        localizedReason: 'Desbloquea MisBolos para continuar',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (success) {
        markUnlocked();
        return BiometricUnlockResult.success;
      }
      return BiometricUnlockResult.cancelled;
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      if (code.contains('notavailable') ||
          code.contains('notenrolled') ||
          code.contains('passcodenotset')) {
        return BiometricUnlockResult.unavailable;
      }
      if (code.contains('usercancel') || code.contains('systemcancel')) {
        return BiometricUnlockResult.cancelled;
      }
      return BiometricUnlockResult.error;
    } catch (_) {
      return BiometricUnlockResult.error;
    } finally {
      _isUnlocking = false;
      notifyListeners();
    }
  }

  void _applyForegroundLockIfNeeded() {
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    if (!hasSession || !isSecurityEnabled) {
      _setLocked(false);
      return;
    }

    _setLocked(!_unlockedForForeground);
  }

  void _setLocked(bool value) {
    if (_isLocked == value) return;
    _isLocked = value;
    notifyListeners();
  }
}
