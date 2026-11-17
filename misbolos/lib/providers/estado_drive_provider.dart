import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/estado_drive.dart';
import 'settings_provider.dart';

/// Cómo está Drive ahora mismo: carpetas creadas y primera sincronización.
final estadoDriveProvider = FutureProvider<EstadoDrive>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  return EstadoDrive(
    carpetasCreadas: await EstadoDriveStore.carpetasCreadas(
      settings.driveRootFolderId,
    ),
    primeraSincronizacionCompleta: settings.lastCloudSyncAt != null,
  );
});
