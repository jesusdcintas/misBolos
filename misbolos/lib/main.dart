import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/constants/supabase_config.dart';
import 'database/database_helper.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _installGlobalErrorHandlers();

    try {
      // Inicializar datos de locale para el calendario
      await initializeDateFormatting('es_ES', null);

      // sqflite FFI para desktop (macOS, Windows, Linux)
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // Inicializar DB invitado; al autenticar se conmuta a DB por usuario.
      await DatabaseHelper.instance.switchToUserDatabase(null);

      // Initialize Supabase
      await SupabaseService.instance.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
    } catch (e) {
      debugPrint('Error en inicialización: $e');
    }

    // Initialize notifications (solo móvil)
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await NotificationService.instance.initialize();
      } catch (e) {
        debugPrint('Error inicializando notificaciones: $e');
      }
    }

    runApp(const ProviderScope(child: MisBolosApp()));
  }, _handleUncaughtError);
}

void _installGlobalErrorHandlers() {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_isRetryableSupabaseNetworkError(details.exception)) {
      debugPrint('[Supabase] Auth refresh offline: ${details.exception}');
      return;
    }
    previousFlutterError?.call(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (_isRetryableSupabaseNetworkError(error)) {
      debugPrint('[Supabase] Auth refresh offline: $error');
      return true;
    }
    return false;
  };
}

void _handleUncaughtError(Object error, StackTrace stack) {
  if (_isRetryableSupabaseNetworkError(error)) {
    debugPrint('[Supabase] Auth refresh offline: $error');
    return;
  }
  FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
}

bool _isRetryableSupabaseNetworkError(Object error) {
  final message = error.toString();
  return message.contains('AuthRetryableFetchException') &&
      (message.contains('Failed host lookup') ||
          message.contains('SocketException') ||
          message.contains('Connection failed') ||
          message.contains('Network is unreachable'));
}
