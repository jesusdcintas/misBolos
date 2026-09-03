import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'platform_auth_service.dart';

/// Credenciales OAuth Desktop de Google Cloud.
const String _googleClientId =
    '744196169382-knr1najrpc3muiim38k3epg6rdmdpuhj.apps.googleusercontent.com';
const String _googleClientSecret = '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';

const String _prefsKeyCredentials = 'google_auth_credentials';
const String _prefsKeyEmail = 'google_auth_email';
// Claves para persistir el estado de Calendar en móvil
const String _prefsKeyMobileCalendarConnected =
    'google_calendar_connected_mobile';
const String _prefsKeyMobileEmail = 'google_calendar_email_mobile';

final _scopes = [
  gcal.CalendarApi.calendarScope,
  gcal.CalendarApi.calendarEventsScope,
  gdrive.DriveApi.driveScope,
  'email',
  'profile',
];

/// Servicio centralizado de autenticación con Google para Desktop.
/// Usa googleapis_auth (clientViaUserConsent) que soporta client_secret.
/// Los tokens OAuth se persisten en SharedPreferences para sobrevivir reinicios.
class GoogleAuthService {
  static final GoogleAuthService instance = GoogleAuthService._();
  GoogleAuthService._();

  auth.AuthClient? _authClient;
  String? _email;

  bool get isSignedIn => _authClient != null;
  String? get userEmail => _email;
  String? get displayName => _email?.split('@').first;
  String? get photoUrl => null;

  Future<bool> signIn() async {
    try {
      debugPrint('[GoogleAuth] signIn() called…');
      final clientId = auth.ClientId(_googleClientId, _googleClientSecret);

      _authClient = await auth.clientViaUserConsent(clientId, _scopes, (
        String url,
      ) async {
        debugPrint('[GoogleAuth] Opening browser: $url');
        await launchUrl(Uri.parse(url));
      });

      // Obtener email real via userinfo
      await _fetchUserEmail();

      // Persistir credenciales para sesiones futuras
      await _persistCredentials();

      debugPrint('[GoogleAuth] signIn() success – $_email');
      return true;
    } catch (e, st) {
      debugPrint('[GoogleAuth] signIn() ERROR: $e\n$st');
      _authClient = null;
      _email = null;
      return false;
    }
  }

  /// Intenta restaurar la sesión desde las credenciales persistidas.
  /// Si el access token expiró, googleapis_auth lo renueva automáticamente
  /// usando el refresh token.
  Future<bool> signInSilently() async {
    if (isSignedIn) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final credsJson = prefs.getString(_prefsKeyCredentials);
      if (credsJson == null) return false;

      final map = jsonDecode(credsJson) as Map<String, dynamic>;
      final atMap = map['accessToken'] as Map<String, dynamic>;

      final credentials = auth.AccessCredentials(
        auth.AccessToken(
          atMap['type'] as String,
          atMap['data'] as String,
          atMap['expiry'] != null
              ? DateTime.parse(atMap['expiry'] as String).toUtc()
              : DateTime.now().toUtc().add(const Duration(seconds: -1)),
        ),
        map['refreshToken'] as String?,
        (map['scopes'] as List).cast<String>(),
      );

      final clientId = auth.ClientId(_googleClientId, _googleClientSecret);
      final baseClient = http.Client();
      _authClient = auth.autoRefreshingClient(
        clientId,
        credentials,
        baseClient,
      );
      _email = prefs.getString(_prefsKeyEmail);

      // Verificar que las credenciales funcionan y actualizar email
      await _fetchUserEmail();

      // Actualizar credenciales persistidas (pueden haber sido renovadas)
      await _persistCredentials();

      debugPrint('[GoogleAuth] signInSilently() restored session – $_email');
      return true;
    } catch (e) {
      debugPrint('[GoogleAuth] signInSilently() failed: $e');
      _authClient = null;
      return false;
    }
  }

  Future<void> signOut() async {
    _authClient?.close();
    _authClient = null;
    _email = null;
    await _clearPersistedCredentials();
  }

  Future<http.Client> get httpClient async {
    if (_authClient == null) throw StateError('No hay sesión de Google activa');
    return _authClient!;
  }

  gcal.CalendarApi? get calendarApi {
    if (_authClient == null) return null;
    return gcal.CalendarApi(_authClient!);
  }

  /// Verifica si el scope de Calendar está activo llamando a la API.
  Future<bool> checkCalendarAccess() async {
    try {
      final api = calendarApi;
      if (api == null) return false;
      await api.calendarList.list(maxResults: 1);
      return true;
    } catch (e) {
      debugPrint('[GoogleAuth] Calendar access check failed: $e');
      return false;
    }
  }

  // ── Helpers privados ──────────────────────────────────────────────────────

  Future<void> _fetchUserEmail() async {
    if (_authClient == null) return;
    try {
      final response = await _authClient!.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      );
      if (response.statusCode == 200) {
        final emailMatch = RegExp(
          r'"email"\s*:\s*"([^"]+)"',
        ).firstMatch(response.body);
        if (emailMatch != null) _email = emailMatch.group(1);
      }
    } catch (e) {
      debugPrint('[GoogleAuth] Could not fetch userinfo: $e');
    }
  }

  Future<void> _persistCredentials() async {
    if (_authClient == null) return;
    try {
      final creds = _authClient!.credentials;
      final json = jsonEncode({
        'accessToken': {
          'data': creds.accessToken.data,
          'type': creds.accessToken.type,
          'expiry': creds.accessToken.expiry.toIso8601String(),
        },
        'refreshToken': creds.refreshToken,
        'scopes': creds.scopes,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyCredentials, json);
      if (_email != null) await prefs.setString(_prefsKeyEmail, _email!);
    } catch (e) {
      debugPrint('[GoogleAuth] Failed to persist credentials: $e');
    }
  }

  Future<void> _clearPersistedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyCredentials);
      await prefs.remove(_prefsKeyEmail);
    } catch (e) {
      debugPrint('[GoogleAuth] Failed to clear credentials: $e');
    }
  }
}

/// Provider para el estado de sesión de Google
final googleAuthProvider =
    StateNotifierProvider<GoogleAuthNotifier, GoogleAuthState>((ref) {
      return GoogleAuthNotifier();
    });

class GoogleAuthState {
  final bool isSignedIn;
  final bool calendarConnected;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  const GoogleAuthState({
    this.isSignedIn = false,
    this.calendarConnected = false,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  GoogleAuthState copyWith({
    bool? isSignedIn,
    bool? calendarConnected,
    String? email,
    String? displayName,
    String? photoUrl,
  }) {
    return GoogleAuthState(
      isSignedIn: isSignedIn ?? this.isSignedIn,
      calendarConnected: calendarConnected ?? this.calendarConnected,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}

class GoogleAuthNotifier extends StateNotifier<GoogleAuthState> {
  GoogleAuthNotifier() : super(const GoogleAuthState()) {
    _tryAutoSignIn();
  }

  // En iOS/Android/macOS usamos PlatformAuthService (sesión Google unificada).
  bool get _usesPlatformAuth =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  Future<void> _tryAutoSignIn() async {
    if (_usesPlatformAuth) {
      final prefs = await SharedPreferences.getInstance();
      final wasConnected =
          prefs.getBool(_prefsKeyMobileCalendarConnected) ?? false;
      final savedEmail = prefs.getString(_prefsKeyMobileEmail);

      final success = await PlatformAuthService.instance.signInSilently();
      if (success) {
        await _updateStateFromPlatform();
        await _saveMobileCalendarState();
      } else if (wasConnected && !Platform.isMacOS) {
        state = GoogleAuthState(
          isSignedIn: true,
          calendarConnected: false,
          email: savedEmail,
          displayName: savedEmail?.split('@').first,
        );
      } else {
        state = const GoogleAuthState();
        if (Platform.isMacOS) {
          await _clearMobileCalendarState();
        }
      }
    } else {
      final success = await GoogleAuthService.instance.signInSilently();
      if (success) await _updateStateFromDesktop();
    }
  }

  Future<bool> signIn() async {
    if (_usesPlatformAuth) {
      final success = await PlatformAuthService.instance.signIn();
      if (success) {
        await _updateStateFromPlatform();
        await _saveMobileCalendarState();
      }
      return success;
    } else {
      final success = await GoogleAuthService.instance.signIn();
      if (success) await _updateStateFromDesktop();
      return success;
    }
  }

  Future<void> signOut() async {
    if (_usesPlatformAuth) {
      await PlatformAuthService.instance.signOut();
      if (Platform.isMacOS) {
        await GoogleAuthService.instance.signOut();
      }
      await _clearMobileCalendarState();
    } else {
      await GoogleAuthService.instance.signOut();
    }
    state = const GoogleAuthState();
  }

  /// Solicita acceso a Calendar sin requerir login completo si ya hay sesión.
  Future<bool> connectCalendarOnly() async {
    if (_usesPlatformAuth) {
      if (PlatformAuthService.instance.isSignedIn) {
        final hasToken = await _hasPlatformCalendarAccess();
        state = state.copyWith(calendarConnected: hasToken);
        if (hasToken) {
          await _saveMobileCalendarState();
          return true;
        }
      }
      if (Platform.isMacOS) {
        final success = await GoogleAuthService.instance.signIn();
        final hasAccess =
            success && await GoogleAuthService.instance.checkCalendarAccess();
        state = GoogleAuthState(
          isSignedIn: success,
          calendarConnected: hasAccess,
          email: GoogleAuthService.instance.userEmail,
          displayName: GoogleAuthService.instance.displayName,
          photoUrl: GoogleAuthService.instance.photoUrl,
        );
        await _saveMobileCalendarState();
        return hasAccess;
      }
      final success = await signIn();
      return success && state.calendarConnected;
    } else {
      final currentUser = GoogleAuthService.instance.isSignedIn;
      if (currentUser) {
        final hasAccess = await GoogleAuthService.instance
            .checkCalendarAccess();
        if (hasAccess) {
          state = state.copyWith(calendarConnected: true);
          return true;
        }
      }
      return await signIn();
    }
  }

  Future<void> _updateStateFromPlatform() async {
    final svc = PlatformAuthService.instance;
    if (!svc.isSignedIn) {
      state = const GoogleAuthState();
      return;
    }
    final calendarConnected = await _hasPlatformCalendarAccess();
    state = GoogleAuthState(
      isSignedIn: true,
      calendarConnected: calendarConnected,
      email: svc.userEmail,
      displayName: svc.displayName,
      photoUrl: svc.photoUrl,
    );
  }

  Future<bool> _hasPlatformCalendarAccess() async {
    final token = await PlatformAuthService.instance.getAccessToken();
    if (token != null && token.isNotEmpty) return true;
    if (Platform.isMacOS) {
      await GoogleAuthService.instance.signInSilently();
      return GoogleAuthService.instance.checkCalendarAccess();
    }
    return false;
  }

  Future<void> _saveMobileCalendarState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _prefsKeyMobileCalendarConnected,
        state.calendarConnected,
      );
      if (state.email != null) {
        await prefs.setString(_prefsKeyMobileEmail, state.email!);
      }
    } catch (e) {
      debugPrint('[GoogleAuth] Failed to save mobile calendar state: $e');
    }
  }

  Future<void> _clearMobileCalendarState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyMobileCalendarConnected);
      await prefs.remove(_prefsKeyMobileEmail);
    } catch (e) {
      debugPrint('[GoogleAuth] Failed to clear mobile calendar state: $e');
    }
  }

  Future<void> _updateStateFromDesktop() async {
    final calendarOk = await GoogleAuthService.instance.checkCalendarAccess();
    state = GoogleAuthState(
      isSignedIn: true,
      calendarConnected: calendarOk,
      email: GoogleAuthService.instance.userEmail,
      displayName: GoogleAuthService.instance.displayName,
      photoUrl: GoogleAuthService.instance.photoUrl,
    );
  }
}
