import 'package:shared_preferences/shared_preferences.dart';

/// Lo que la app sabe de cómo está Drive en este dispositivo.
///
/// Lo consulta la guía del tutorial para saber si queda algo por hacer.
class EstadoDrive {
  /// Si ya se montó el árbol de carpetas en la carpeta de trabajo actual.
  final bool carpetasCreadas;

  /// Si ha terminado alguna vez una sincronización completa con la nube.
  final bool primeraSincronizacionCompleta;

  const EstadoDrive({
    required this.carpetasCreadas,
    required this.primeraSincronizacionCompleta,
  });

  bool get todoListo => carpetasCreadas && primeraSincronizacionCompleta;
}

/// Guarda si las carpetas ya están creadas, por carpeta de trabajo.
///
/// Va por carpeta raíz a propósito: si el usuario elige otra carpeta de
/// Drive, lo de antes no cuenta y hay que volver a montarlas.
class EstadoDriveStore {
  static String _clave(String rootFolderId) =>
      'drive_carpetas_creadas_$rootFolderId';

  static Future<bool> carpetasCreadas(String? rootFolderId) async {
    final id = rootFolderId?.trim();
    if (id == null || id.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_clave(id)) ?? false;
  }

  static Future<void> marcarCarpetasCreadas(String? rootFolderId) async {
    final id = rootFolderId?.trim();
    if (id == null || id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_clave(id), true);
  }

  /// Olvida las carpetas creadas de todas las carpetas de trabajo.
  ///
  /// Estas marcas viven en SharedPreferences, que es del dispositivo y no de
  /// la cuenta: al cambiar de cuenta hay que borrarlas para que la nueva no
  /// herede el «ya está» de la anterior.
  static Future<void> limpiarTodo() async {
    final prefs = await SharedPreferences.getInstance();
    final claves = prefs
        .getKeys()
        .where((k) => k.startsWith('drive_carpetas_creadas_'))
        .toList();
    for (final clave in claves) {
      await prefs.remove(clave);
    }
  }
}
