import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'supabase_service.dart';

/// Servicio de autenticación con Google para sincronización con Supabase
/// Soporta iOS, Android y macOS
class PlatformAuthService {
  static final PlatformAuthService instance = PlatformAuthService._();
  PlatformAuthService._();

  // Para iOS/Android usamos google_sign_in
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
      'https://www.googleapis.com/auth/calendar',
      'https://www.googleapis.com/auth/calendar.events',
      'https://www.googleapis.com/auth/drive',
    ],
  );

  GoogleSignInAccount? _currentUser;
  String? _idToken;
  String? _accessToken;

  bool get isSignedIn {
    if (Platform.isMacOS) {
      return SupabaseService.instance.isAuthenticated;
    }
    return _currentUser != null;
  }

  String? get userEmail {
    if (Platform.isMacOS) return SupabaseService.instance.userEmail;
    return _currentUser?.email;
  }

  String? get displayName {
    if (Platform.isMacOS) {
      // Supabase no tiene displayName, usar la parte antes de @ del email
      final email = SupabaseService.instance.userEmail;
      return email?.split('@').first;
    }
    return _currentUser?.displayName;
  }

  String? get photoUrl {
    // Supabase no proporciona photoUrl directamente
    if (Platform.isMacOS) return null;
    return _currentUser?.photoUrl;
  }

  /// Indica si la plataforma actual soporta sincronización
  static bool get isSupported =>
      Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  /// Inicia sesión con Google y autentica en Supabase
  Future<bool> signIn() async {
    if (!isSupported) {
      debugPrint('[PlatformAuth] No soportado en esta plataforma');
      return false;
    }

    // En macOS usamos GoogleAuthService que soporta client_secret
    if (Platform.isMacOS) {
      return await _signInMacOS();
    }

    // En iOS/Android usamos google_sign_in
    return await _signInMobile();
  }

  Future<bool> _signInMacOS() async {
    try {
      debugPrint('[PlatformAuth] macOS signIn via Supabase OAuth…');

      // En macOS usamos el OAuth de Supabase directamente
      // Esto abre el navegador y maneja el callback automáticamente
      final success = await SupabaseService.instance.signInWithOAuth();

      if (!success) {
        debugPrint('[PlatformAuth] macOS OAuth failed to start');
        return false;
      }

      debugPrint(
        '[PlatformAuth] macOS OAuth initiated - waiting for callback...',
      );

      // Esperar un momento para que el callback se procese
      await Future.delayed(const Duration(seconds: 1));

      // Verificar si la autenticación fue exitosa
      if (SupabaseService.instance.isAuthenticated) {
        debugPrint(
          '[PlatformAuth] macOS OAuth success: ${SupabaseService.instance.userEmail}',
        );
        return true;
      }

      debugPrint(
        '[PlatformAuth] macOS OAuth - user completing auth in browser',
      );
      return true; // El flujo continúa en el navegador
    } catch (e) {
      debugPrint('[PlatformAuth] macOS signIn() ERROR: $e');
      return false;
    }
  }

  Future<bool> _signInMobile() async {
    try {
      debugPrint('[PlatformAuth] signIn() called…');

      final account = await _googleSignIn.signIn();
      if (account == null) {
        debugPrint('[PlatformAuth] User cancelled sign in');
        return false;
      }

      _currentUser = account;

      // Obtener tokens
      final auth = await account.authentication;
      _idToken = auth.idToken;
      _accessToken = auth.accessToken;

      debugPrint('[PlatformAuth] Signed in as ${account.email}');
      debugPrint('[PlatformAuth] Has idToken: ${_idToken != null}');

      // Autenticar en Supabase
      if (_idToken != null && _accessToken != null) {
        final supabaseSuccess = await SupabaseService.instance.signInWithGoogle(
          _idToken!,
          _accessToken!,
        );
        debugPrint('[PlatformAuth] Supabase auth: $supabaseSuccess');
      }

      return true;
    } catch (e) {
      debugPrint('[PlatformAuth] signIn() ERROR: $e');
      return false;
    }
  }

  Future<bool> signInSilently() async {
    if (!isSupported) return false;

    // En macOS, verificar si Supabase tiene sesión activa
    if (Platform.isMacOS) {
      return SupabaseService.instance.isAuthenticated;
    }

    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return false;

      _currentUser = account;

      final auth = await account.authentication;
      _idToken = auth.idToken;
      _accessToken = auth.accessToken;

      if (_idToken != null && _accessToken != null) {
        await SupabaseService.instance.signInWithGoogle(
          _idToken!,
          _accessToken!,
        );
      }

      return true;
    } catch (e) {
      debugPrint('[PlatformAuth] signInSilently() ERROR: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    if (Platform.isMacOS) {
      await SupabaseService.instance.signOut();
    } else {
      await _googleSignIn.signOut();
      await SupabaseService.instance.signOut();
    }
    _currentUser = null;
    _idToken = null;
    _accessToken = null;
  }

  /// Devuelve un access token fresco de Google en móvil.
  /// En macOS no aplica (se usa otro flujo OAuth).
  Future<String?> getAccessToken() async {
    if (Platform.isMacOS) return null;
    if (_currentUser == null) return null;
    try {
      final auth = await _currentUser!.authentication;
      _accessToken = auth.accessToken;
      return _accessToken;
    } catch (e) {
      debugPrint('[PlatformAuth] getAccessToken() ERROR: $e');
      return null;
    }
  }

  /// Reconectar con Supabase si ya hay sesión de Google
  Future<bool> reconnectSupabase() async {
    if (Platform.isMacOS) {
      // En macOS, la sesión se mantiene via Supabase
      return SupabaseService.instance.isAuthenticated;
    }

    if (_currentUser == null) return false;

    try {
      final auth = await _currentUser!.authentication;
      _idToken = auth.idToken;
      _accessToken = auth.accessToken;

      if (_idToken != null && _accessToken != null) {
        return await SupabaseService.instance.signInWithGoogle(
          _idToken!,
          _accessToken!,
        );
      }
      return false;
    } catch (e) {
      debugPrint('[PlatformAuth] reconnectSupabase() ERROR: $e');
      return false;
    }
  }
}
