import 'dart:io';
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
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Inicializar datos de locale para el calendario
    await initializeDateFormatting('es_ES', null);

    // sqflite FFI para desktop (macOS, Windows, Linux)
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    // Initialize database
    await DatabaseHelper.instance.database;

    // Initialize Supabase
    await SupabaseService.instance.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );

    // Initialize notifications (solo móvil)
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await NotificationService.instance.initialize();
      } catch (e) {
        debugPrint('Error inicializando notificaciones: $e');
      }
    }
  } catch (e) {
    debugPrint('Error en inicialización: $e');
  }

  runApp(
    const ProviderScope(
      child: MisBolosApp(),
    ),
  );
}
