import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database_helper.dart';
import '../repositories/settings_repository.dart';
import '../services/google_auth_service.dart';
import '../services/platform_auth_service.dart';
import '../services/supabase_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated, loading, error }

class AuthUiState {
  final AuthStatus status;
  final String? message;

  const AuthUiState({this.status = AuthStatus.unknown, this.message});

  AuthUiState copyWith({AuthStatus? status, String? message}) {
    return AuthUiState(
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

final authSessionProvider = StreamProvider<Session?>((ref) {
  final stream = SupabaseService.instance.authStateChanges;
  if (stream == null) {
    return Stream.value(Supabase.instance.client.auth.currentSession);
  }
  return stream.map((event) => event.session);
});

final authControllerProvider =
    NotifierProvider<AuthController, AuthUiState>(AuthController.new);

class AuthController extends Notifier<AuthUiState> {
  StreamSubscription<AuthState>? _authSub;

  @override
  AuthUiState build() {
    _authSub?.cancel();
    _authSub = SupabaseService.instance.authStateChanges?.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        state = const AuthUiState(status: AuthStatus.unauthenticated);
      } else if (event.session != null) {
        state = const AuthUiState(status: AuthStatus.authenticated);
      }
    });
    ref.onDispose(() {
      _authSub?.cancel();
      _authSub = null;
    });

    final hasSession = Supabase.instance.client.auth.currentSession != null;
    return AuthUiState(
      status: hasSession
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated,
    );
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AuthUiState(status: AuthStatus.loading);
    try {
      final response = await SupabaseService.instance.signInWithEmailPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) {
        state = const AuthUiState(
          status: AuthStatus.error,
          message: 'No se pudo iniciar sesión.',
        );
        return false;
      }
      state = const AuthUiState(status: AuthStatus.authenticated);
      return true;
    } on AuthException catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.message),
      );
      return false;
    } catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.toString()),
      );
      return false;
    }
  }

  Future<bool> registerWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AuthUiState(status: AuthStatus.loading);
    try {
      final response = await SupabaseService.instance.signUpWithEmailPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) {
        state = const AuthUiState(
          status: AuthStatus.error,
          message: 'No se pudo crear la cuenta.',
        );
        return false;
      }

      final needsConfirm = response.session == null;
      state = AuthUiState(
        status: needsConfirm
            ? AuthStatus.unauthenticated
            : AuthStatus.authenticated,
        message: needsConfirm
            ? 'Cuenta creada. Revisa tu email para confirmar la cuenta.'
            : 'Cuenta creada correctamente.',
      );
      return true;
    } on AuthException catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.message),
      );
      return false;
    } catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.toString()),
      );
      return false;
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    state = const AuthUiState(status: AuthStatus.loading);
    try {
      await SupabaseService.instance.sendPasswordResetEmail(email: email.trim());
      state = const AuthUiState(
        status: AuthStatus.unauthenticated,
        message: 'Te hemos enviado un email para recuperar contraseña.',
      );
      return true;
    } on AuthException catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.message),
      );
      return false;
    } catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.toString()),
      );
      return false;
    }
  }

  Future<bool> updatePassword({
    required String newPassword,
  }) async {
    state = const AuthUiState(status: AuthStatus.loading);
    try {
      await SupabaseService.instance.updatePassword(newPassword);
      state = const AuthUiState(
        status: AuthStatus.authenticated,
        message: 'Contraseña actualizada correctamente.',
      );
      return true;
    } on AuthException catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.message),
      );
      return false;
    } catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.toString()),
      );
      return false;
    }
  }

  Future<bool> signOut() async {
    state = const AuthUiState(status: AuthStatus.loading);
    try {
      await SupabaseService.instance.signOut();
      await PlatformAuthService.instance.signOut();
      await GoogleAuthService.instance.signOut();
      await DatabaseHelper.instance.clearUserScopedData();
      final settingsRepo = SettingsRepository();
      final currentSettings = await settingsRepo.get();
      await settingsRepo.save(currentSettings.copyWith(lastCloudSyncAt: null));
      state = const AuthUiState(status: AuthStatus.unauthenticated);
      return true;
    } catch (e) {
      debugPrint('[Auth] signOut error: $e');
      state = AuthUiState(
        status: AuthStatus.error,
        message: 'No se pudo cerrar sesión.',
      );
      return false;
    }
  }

  Future<bool> signInWithGoogle() async {
    state = const AuthUiState(status: AuthStatus.loading);
    try {
      final success = await PlatformAuthService.instance.signIn();
      if (!success || !SupabaseService.instance.isAuthenticated) {
        state = const AuthUiState(
          status: AuthStatus.error,
          message: 'No se pudo iniciar sesión con Google.',
        );
        return false;
      }
      state = const AuthUiState(status: AuthStatus.authenticated);
      return true;
    } catch (e) {
      state = AuthUiState(
        status: AuthStatus.error,
        message: _friendlyAuthMessage(e.toString()),
      );
      return false;
    }
  }

  String _friendlyAuthMessage(String raw) {
    final msg = raw.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Credenciales incorrectas.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Debes confirmar tu email antes de iniciar sesión.';
    }
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('failed host lookup')) {
      return 'Problema de red. Revisa tu conexión.';
    }
    return raw;
  }
}
