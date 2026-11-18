import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/estado_drive.dart';
import '../core/services/google_drive_service.dart';
import '../services/google_auth_service.dart';
import 'settings_provider.dart';

/// Cómo está Drive ahora mismo: carpetas creadas y primera sincronización.
final estadoDriveProvider = FutureProvider<EstadoDrive>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  final rootId = settings.driveRootFolderId?.trim();

  var carpetasCreadas = await EstadoDriveStore.carpetasCreadas(rootId);

  // Las carpetas pueden haberse creado en otro dispositivo: aquí no consta la
  // marca local, pero si la carpeta raíz guardada sigue viva en Drive (y no en
  // la papelera), el paso está hecho igual. Se guarda la marca para no volver
  // a preguntarlo a Drive.
  if (!carpetasCreadas &&
      (rootId?.isNotEmpty ?? false) &&
      ref.watch(googleAuthProvider).isSignedIn) {
    try {
      final revision = await GoogleDriveService.instance.revisarRaiz();
      if (revision.sePuedeUsar) {
        carpetasCreadas = true;
        await EstadoDriveStore.marcarCarpetasCreadas(rootId);
      }
    } catch (_) {
      // Sin red no se puede confirmar: el paso se queda como estaba.
    }
  }

  return EstadoDrive(
    carpetasCreadas: carpetasCreadas,
    primeraSincronizacionCompleta: settings.lastCloudSyncAt != null,
  );
});
