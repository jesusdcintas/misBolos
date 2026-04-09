import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Credenciales OAuth Desktop de Google Cloud.
const String _googleClientId =
    '744196169382-knr1najrpc3muiim38k3epg6rdmdpuhj.apps.googleusercontent.com';
const String _googleClientSecret = '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';

final _scopes = [
  gcal.CalendarApi.calendarScope,
  drive.DriveApi.driveFileScope,
  'email',
  'profile',
];

/// Servicio centralizado de autenticación con Google para Desktop.
/// Usa googleapis_auth (clientViaUserConsent) que soporta client_secret.
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

      _authClient = await auth.clientViaUserConsent(
        clientId,
        _scopes,
        (String url) async {
          debugPrint('[GoogleAuth] Opening browser: $url');
          await launchUrl(Uri.parse(url));
        },
      );

      // Obtener email del perfil vía People API o Calendar settings
      try {
        final calApi = gcal.CalendarApi(_authClient!);
        final setting = await calApi.settings.get('timezone');
        // Si llegamos aquí, la API funciona. Obtenemos el email del token.
        debugPrint('[GoogleAuth] Calendar API OK (tz: ${setting.value})');
      } catch (_) {}

      // Obtener email real via userinfo
      try {
        final response = await _authClient!.get(
          Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        );
        if (response.statusCode == 200) {
          final body = response.body;
          // Parsear JSON manualmente para no añadir dependencias
          final emailMatch = RegExp(r'"email"\s*:\s*"([^"]+)"').firstMatch(body);
          if (emailMatch != null) {
            _email = emailMatch.group(1);
          }
        }
      } catch (e) {
        debugPrint('[GoogleAuth] Could not fetch userinfo: $e');
      }

      debugPrint('[GoogleAuth] signIn() success – $_email');
      return true;
    } catch (e, st) {
      debugPrint('[GoogleAuth] signIn() ERROR: $e\n$st');
      _authClient = null;
      _email = null;
      return false;
    }
  }

  Future<bool> signInSilently() async {
    // googleapis_auth no persiste tokens automáticamente en desktop.
    // Solo tendremos sesión si ya se hizo signIn() en esta ejecución.
    return isSignedIn;
  }

  Future<void> signOut() async {
    _authClient?.close();
    _authClient = null;
    _email = null;
  }

  Future<http.Client> get httpClient async {
    if (_authClient == null) throw StateError('No hay sesión de Google activa');
    return _authClient!;
  }

  gcal.CalendarApi? get calendarApi {
    if (_authClient == null) return null;
    return gcal.CalendarApi(_authClient!);
  }

  drive.DriveApi? get driveApi {
    if (_authClient == null) return null;
    return drive.DriveApi(_authClient!);
  }
}

/// Provider para el estado de sesión de Google
final googleAuthProvider =
    StateNotifierProvider<GoogleAuthNotifier, GoogleAuthState>((ref) {
  return GoogleAuthNotifier();
});

class GoogleAuthState {
  final bool isSignedIn;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  const GoogleAuthState({
    this.isSignedIn = false,
    this.email,
    this.displayName,
    this.photoUrl,
  });

  GoogleAuthState copyWith({
    bool? isSignedIn,
    String? email,
    String? displayName,
    String? photoUrl,
  }) {
    return GoogleAuthState(
      isSignedIn: isSignedIn ?? this.isSignedIn,
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

  Future<void> _tryAutoSignIn() async {
    final success = await GoogleAuthService.instance.signInSilently();
    if (success) {
      _updateState();
    }
  }

  Future<bool> signIn() async {
    final success = await GoogleAuthService.instance.signIn();
    if (success) {
      _updateState();
    }
    return success;
  }

  Future<void> signOut() async {
    await GoogleAuthService.instance.signOut();
    state = const GoogleAuthState();
  }

  void _updateState() {
    state = GoogleAuthState(
      isSignedIn: true,
      email: GoogleAuthService.instance.userEmail,
      displayName: GoogleAuthService.instance.displayName,
      photoUrl: GoogleAuthService.instance.photoUrl,
    );
  }
}
