import 'arbol_drive.dart';
import 'estado_raiz_drive.dart';

export 'arbol_drive.dart';
export 'estado_raiz_drive.dart';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../repositories/settings_repository.dart';
import '../../services/google_auth_service.dart';
import '../../services/platform_auth_service.dart';

class GoogleAccount {
  final String? email;
  final String? displayName;

  const GoogleAccount({this.email, this.displayName});
}

class DriveFolderResult {
  final String id;
  final String name;
  final String? webViewLink;

  const DriveFolderResult({
    required this.id,
    required this.name,
    this.webViewLink,
  });
}

class DriveMonthFolders {
  final String yearFolderId;
  final String quarterFolderId;
  final String monthFolderId;
  final String facturasFolderId;

  /// Donde van los adjuntos de gastos y de inversiones.
  final String gastosInversionesFolderId;

  const DriveMonthFolders({
    required this.yearFolderId,
    required this.quarterFolderId,
    required this.monthFolderId,
    required this.facturasFolderId,
    required this.gastosInversionesFolderId,
  });
}

class DriveUploadResult {
  final String fileId;
  final String? fileUrl;

  const DriveUploadResult({required this.fileId, this.fileUrl});
}

class DriveBackupFile {
  final String id;
  final String name;
  final DateTime? createdAt;
  final int? sizeBytes;

  const DriveBackupFile({
    required this.id,
    required this.name,
    this.createdAt,
    this.sizeBytes,
  });
}

class DriveExistingFileResult {
  final String fileId;
  final String? fileUrl;

  const DriveExistingFileResult({required this.fileId, this.fileUrl});
}

class DriveWorkspaceSetupResult {
  /// Si Drive queda usable: hay cuenta y carpeta de trabajo elegida.
  final bool ready;

  final bool autoConfigured;
  final String? message;
  final DriveFolderResult? folder;

  /// Si además se pudo montar el árbol de carpetas del año.
  ///
  /// Va aparte de [ready] a propósito: que falle una carpeta no deja Drive
  /// sin conectar, y se vuelve a intentar solo cuando haga falta.
  final bool estructuraCompleta;

  const DriveWorkspaceSetupResult({
    required this.ready,
    required this.autoConfigured,
    this.message,
    this.folder,
    this.estructuraCompleta = true,
  });
}

enum DriveConnectionStatus {
  disconnected,
  googleConnectedNoDrive,
  missingFolder,
  permissionMissing,
  folderNotAccessible,
  connected,
  error,
}

class DriveConnectionCheck {
  final DriveConnectionStatus status;
  final String message;
  final GoogleAccount? account;
  final String? folderId;
  final String? folderName;
  final Object? error;

  const DriveConnectionCheck({
    required this.status,
    required this.message,
    this.account,
    this.folderId,
    this.folderName,
    this.error,
  });

  bool get isConnected => status == DriveConnectionStatus.connected;
}

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._();
  GoogleDriveService._();

  final SettingsRepository _settingsRepository = SettingsRepository();
  final Map<String, String> _folderIdCache = {};
  final Map<String, DriveMonthFolders> _monthStructureCache = {};

  bool get _usesPlatformAuth =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  Future<DriveConnectionCheck> checkDriveConnectionStatus() async {
    final settings = await _settingsRepository.get();
    final account = await getCurrentAccount();
    final hasGoogleAccount =
        GoogleAuthService.instance.isSignedIn ||
        PlatformAuthService.instance.isSignedIn;
    if (!hasGoogleAccount) {
      await _persistDriveConnected(false);
      final result = DriveConnectionCheck(
        status: DriveConnectionStatus.disconnected,
        message: 'Sesión caducada, vuelve a conectar',
        account: account,
      );
      _logStatus(result);
      return result;
    }

    final folderId = settings.driveRootFolderId?.trim();
    final folderName = settings.driveRootFolderName?.trim();
    drive.DriveApi api;
    try {
      api = await _driveApi();
    } catch (e) {
      await _persistDriveConnected(false);
      final result = DriveConnectionCheck(
        status: _looksLikePermissionError(e)
            ? DriveConnectionStatus.permissionMissing
            : DriveConnectionStatus.googleConnectedNoDrive,
        message: _looksLikePermissionError(e)
            ? 'Permisos insuficientes'
            : 'Sesión caducada, vuelve a conectar',
        account: account,
        folderId: folderId,
        folderName: folderName,
        error: e,
      );
      _logStatus(result);
      return result;
    }

    if (folderId == null || folderId.isEmpty) {
      await _persistDriveConnected(false);
      final result = DriveConnectionCheck(
        status: DriveConnectionStatus.missingFolder,
        message: 'Drive conectado a Google, pero falta seleccionar carpeta',
        account: account,
      );
      _logStatus(result);
      return result;
    }

    try {
      final folder =
          await api.files.get(
                folderId,
                $fields: 'id,name,mimeType,trashed',
                supportsAllDrives: true,
              )
              as drive.File;
      final accessible =
          folder.id != null &&
          folder.trashed != true &&
          folder.mimeType == 'application/vnd.google-apps.folder';
      if (!accessible) {
        await _persistDriveConnected(false);
        final result = DriveConnectionCheck(
          status: DriveConnectionStatus.folderNotAccessible,
          message: 'No se puede acceder a la carpeta seleccionada',
          account: account,
          folderId: folderId,
          folderName: folderName,
        );
        _logStatus(result);
        return result;
      }
      await _settingsRepository.save(
        settings.copyWith(
          driveConnected: true,
          driveRootFolderName: folder.name ?? folderName,
          driveAccountEmail: account?.email ?? settings.driveAccountEmail,
          driveAccountName: account?.displayName ?? settings.driveAccountName,
        ),
      );
      final result = DriveConnectionCheck(
        status: DriveConnectionStatus.connected,
        message: 'Drive conectado',
        account: account,
        folderId: folderId,
        folderName: folder.name ?? folderName,
      );
      _logStatus(result);
      return result;
    } catch (e) {
      await _persistDriveConnected(false);
      final result = DriveConnectionCheck(
        status: _looksLikePermissionError(e)
            ? DriveConnectionStatus.permissionMissing
            : DriveConnectionStatus.folderNotAccessible,
        message: _looksLikePermissionError(e)
            ? 'Permisos insuficientes'
            : 'No se puede acceder a la carpeta seleccionada',
        account: account,
        folderId: folderId,
        folderName: folderName,
        error: e,
      );
      _logStatus(result);
      return result;
    }
  }

  Future<void> signIn() async {
    final success = _usesPlatformAuth
        ? await PlatformAuthService.instance.signIn()
        : await GoogleAuthService.instance.signIn();

    if (!success) {
      throw Exception('No se pudo conectar con Google Drive.');
    }
    if (!kIsWeb && Platform.isMacOS) {
      final token = await PlatformAuthService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        final desktopSuccess = await GoogleAuthService.instance.signIn();
        if (!desktopSuccess) {
          throw Exception('Permisos insuficientes');
        }
      }
    }

    final settings = await _settingsRepository.get();
    final account = await getCurrentAccount();
    await _settingsRepository.save(
      settings.copyWith(
        driveConnected: false,
        driveAccountEmail: account?.email,
        driveAccountName: account?.displayName,
      ),
    );
  }

  Future<DriveWorkspaceSetupResult> setupWorkspace({
    String defaultFolderName = 'MisBolos',
  }) async {
    try {
      DriveFolderResult? selected;
      final candidates = await searchFoldersByName(defaultFolderName);
      for (final folder in candidates) {
        if (folder.name.trim().toLowerCase() ==
            defaultFolderName.trim().toLowerCase()) {
          selected = folder;
          break;
        }
      }

      selected ??= await _createRootFolder(defaultFolderName);
      await selectRootFolder(selected);

      // A partir de aquí Drive ya está conectado y con carpeta: si alguna
      // carpeta del año falla, se avisa, pero la conexión es buena.
      var estructuraCompleta = true;
      String? aviso;
      try {
        await createFullYearStructure(DateTime.now().year);
      } catch (e) {
        estructuraCompleta = false;
        aviso =
            'Drive quedó conectado, pero no se pudieron crear todas las '
            'carpetas del año. Puedes reintentarlo desde «Crear estructura».';
        debugPrint('[DRIVE][SETUP] estructura incompleta: $e');
      }

      return DriveWorkspaceSetupResult(
        ready: true,
        autoConfigured: true,
        folder: selected,
        estructuraCompleta: estructuraCompleta,
        message: aviso,
      );
    } catch (e) {
      return DriveWorkspaceSetupResult(
        ready: false,
        autoConfigured: false,
        message: e.toString(),
      );
    }
  }

  Future<void> signOut() async {
    _clearFolderCache();
    final settings = await _settingsRepository.get();
    await _settingsRepository.save(
      settings.copyWith(
        driveConnected: false,
        clearDriveAccount: true,
        clearDriveRootFolder: true,
      ),
    );
  }

  Future<bool> isConnected() async {
    return (await checkDriveConnectionStatus()).isConnected;
  }

  Future<GoogleAccount?> getCurrentAccount() async {
    if (_usesPlatformAuth) {
      if (!kIsWeb &&
          Platform.isMacOS &&
          GoogleAuthService.instance.userEmail?.trim().isNotEmpty == true) {
        return GoogleAccount(
          email: GoogleAuthService.instance.userEmail,
          displayName: GoogleAuthService.instance.displayName,
        );
      }
      return GoogleAccount(
        email: PlatformAuthService.instance.userEmail,
        displayName: PlatformAuthService.instance.displayName,
      );
    }
    return GoogleAccount(
      email: GoogleAuthService.instance.userEmail,
      displayName: GoogleAuthService.instance.displayName,
    );
  }

  Future<List<DriveFolderResult>> searchFoldersByName(String name) async {
    final api = await _driveApi();
    final cleanName = name.trim();
    if (cleanName.isEmpty) return [];

    final result = await api.files.list(
      q:
          "mimeType = 'application/vnd.google-apps.folder' "
          "and trashed = false "
          "and name contains '${_escapeQuery(cleanName)}'",
      spaces: 'drive',
      $fields: 'files(id,name,webViewLink)',
      orderBy: 'name',
      pageSize: 20,
    );

    return (result.files ?? [])
        .where((file) => file.id != null && file.name != null)
        .map(
          (file) => DriveFolderResult(
            id: file.id!,
            name: file.name!,
            webViewLink: file.webViewLink,
          ),
        )
        .toList();
  }

  Future<void> selectRootFolder(DriveFolderResult folder) async {
    _clearFolderCache();
    final settings = await _settingsRepository.get();
    final account = await getCurrentAccount();
    await _settingsRepository.save(
      settings.copyWith(
        driveConnected: false,
        driveRootFolderId: folder.id,
        driveRootFolderName: folder.name,
        driveAccountEmail: account?.email ?? settings.driveAccountEmail,
        driveAccountName: account?.displayName ?? settings.driveAccountName,
      ),
    );
    final status = await checkDriveConnectionStatus();
    if (!status.isConnected) {
      throw Exception(status.message);
    }
  }

  Future<bool> restoreSilently() async {
    final settings = await _settingsRepository.get();
    if ((settings.driveRootFolderId ?? '').isEmpty) return false;

    final success = _usesPlatformAuth
        ? await PlatformAuthService.instance.signInSilently()
        : await GoogleAuthService.instance.signInSilently();
    if (!success) {
      return false;
    }

    final status = await checkDriveConnectionStatus();
    return status.isConnected;
  }

  Future<String> ensureRootFolder() {
    return _requiredRootFolderId();
  }

  /// Mira si la carpeta de trabajo sigue viva en Drive.
  ///
  /// Una carpeta en la papelera admite hijos nuevos sin rechistar, así que
  /// sin esta comprobación la app creaba el árbol dentro de la basura y
  /// decía que todo estaba listo.
  Future<RevisionRaizDrive> revisarRaiz() async {
    final settings = await _settingsRepository.get();
    final folderId = settings.driveRootFolderId?.trim();
    if (folderId == null || folderId.isEmpty) {
      return revisarRaizDrive(folderId: null, existe: false, enPapelera: false);
    }

    try {
      final api = await _driveApi();
      final folder =
          await api.files.get(
                folderId,
                $fields: 'id,trashed',
                supportsAllDrives: true,
              )
              as drive.File;
      return revisarRaizDrive(
        folderId: folderId,
        existe: folder.id != null,
        enPapelera: folder.trashed == true,
      );
    } catch (e) {
      debugPrint('[DRIVE][RAIZ] no accesible id=$folderId error=$e');
      return revisarRaizDrive(
        folderId: folderId,
        existe: false,
        enPapelera: false,
      );
    }
  }

  /// Si estos ficheros siguen vivos en Drive.
  ///
  /// Una llamada por fichero, que es lo que hay: Drive no deja preguntar por
  /// varios ids a la vez. Van en paralelo con tope para no castigar la cuota.
  /// Un fichero que no se pueda consultar se queda fuera del resultado, para
  /// que quien decida no lo tome por perdido.
  Future<Map<String, bool>> comprobarFicheros(
    Iterable<String> idsFichero, {
    int limite = 5,
  }) async {
    final ids = idsFichero
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return const {};

    final api = await _driveApi();
    final vivos = <String, bool>{};

    await ejecutarEnParalelo([
      for (final id in ids)
        () async {
          try {
            final fichero =
                await api.files.get(
                      id,
                      $fields: 'id,trashed',
                      supportsAllDrives: true,
                    )
                    as drive.File;
            vivos[id] = fichero.id != null && fichero.trashed != true;
          } catch (e) {
            final texto = e.toString();
            // Un 404 es un «ya no está»; lo demás es duda y se deja fuera.
            if (texto.contains('404') || texto.contains('notFound')) {
              vivos[id] = false;
            } else {
              debugPrint('[DRIVE][FICHEROS] no se pudo comprobar $id: $e');
            }
          }
        },
    ], limite: limite);

    return vivos;
  }

  /// Igual que [revisarRaiz], pero se planta si no se puede usar.
  ///
  /// Además vacía las cachés de ids: si la raíz ya no vale, lo que hubiera
  /// apuntado dentro tampoco.
  Future<void> exigirRaizUsable() async {
    final revision = await revisarRaiz();
    if (revision.sePuedeUsar) return;
    _clearFolderCache();
    throw RaizDriveNoDisponible(revision);
  }

  Future<String> ensureFolder({
    required String parentId,
    required String folderName,
  }) async {
    final normalizedName = folderName.trim();
    final cacheKey = _folderCacheKey(parentId, normalizedName);
    final cached = _folderIdCache[cacheKey];
    if (cached != null) return cached;

    final api = await _driveApi();
    final existing = await api.files.list(
      q:
          "mimeType = 'application/vnd.google-apps.folder' "
          "and trashed = false "
          "and '${_escapeQuery(parentId)}' in parents "
          "and name = '${_escapeQuery(normalizedName)}'",
      spaces: 'drive',
      $fields: 'files(id,name)',
      pageSize: 10,
    );

    final files = existing.files ?? [];
    if (files.isNotEmpty && files.first.id != null) {
      final id = files.first.id!;
      _folderIdCache[cacheKey] = id;
      return id;
    }

    final folder = drive.File()
      ..name = normalizedName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentId];

    final created = await api.files.create(folder, $fields: 'id');
    final id = created.id;
    if (id == null) {
      throw Exception('Google Drive no devolvió ID para $normalizedName.');
    }
    _folderIdCache[cacheKey] = id;
    return id;
  }

  /// Las subcarpetas que cuelgan de [parentId].
  Future<List<CarpetaDrive>> listarSubcarpetas(String parentId) async {
    final api = await _driveApi();
    final resultado = await api.files.list(
      q:
          "mimeType = 'application/vnd.google-apps.folder' "
          "and trashed = false "
          "and '${_escapeQuery(parentId)}' in parents",
      spaces: 'drive',
      $fields: 'files(id,name)',
      pageSize: 100,
    );
    return [
      for (final f in resultado.files ?? const <drive.File>[])
        if (f.id != null && f.name != null)
          CarpetaDrive(id: f.id!, nombre: f.name!),
    ];
  }

  /// Deja lista la carpeta de gastos e inversiones de un mes.
  ///
  /// Si existe la antigua («Gastos e Inversiones») se renombra en su sitio:
  /// ni se crea otra ni se mueve ningún fichero. Si por lo que sea están las
  /// dos, no se fusionan; se usa la de mayúsculas y queda el aviso en el
  /// registro, porque juntarlas sería mover ficheros del usuario.
  Future<String> asegurarCarpetaGastos(String monthFolderId) async {
    final cacheKey = _folderCacheKey(monthFolderId, carpetaGastosEInversiones);
    final cached = _folderIdCache[cacheKey];
    if (cached != null) return cached;

    final decision = decidirCarpetaGastos(
      await listarSubcarpetas(monthFolderId),
    );

    String id;
    switch (decision.accion) {
      case AccionCarpetaGastos.crear:
        id = await ensureFolder(
          parentId: monthFolderId,
          folderName: carpetaGastosEInversiones,
        );
      case AccionCarpetaGastos.usar:
        id = decision.id!;
      case AccionCarpetaGastos.renombrar:
        id = decision.id!;
        await renombrarCarpeta(id: id, nombre: carpetaGastosEInversiones);
        debugPrint(
          '[DRIVE][CARPETAS] renombrada a $carpetaGastosEInversiones id=$id',
        );
      case AccionCarpetaGastos.duplicadas:
        id = decision.id!;
        debugPrint(
          '[DRIVE][CARPETAS][AVISO] en el mes $monthFolderId conviven '
          '«$carpetaGastosEInversiones» y la antigua. Se usa la de '
          'mayúsculas y no se toca la otra.',
        );
    }

    _folderIdCache[cacheKey] = id;
    return id;
  }

  Future<void> renombrarCarpeta({
    required String id,
    required String nombre,
  }) async {
    final api = await _driveApi();
    await api.files.update(drive.File()..name = nombre, id);
  }

  Future<String> ensureYearFolder({
    required String rootFolderId,
    required int year,
  }) {
    return ensureFolder(
      parentId: rootFolderId,
      folderName: getYearFolderName(DateTime(year)),
    );
  }

  Future<String> ensureQuarterFolder({
    required String yearFolderId,
    required DateTime date,
  }) {
    return ensureFolder(
      parentId: yearFolderId,
      folderName: getQuarterName(date),
    );
  }

  Future<String> ensureMonthFolder({
    required String quarterFolderId,
    required DateTime date,
  }) {
    return ensureFolder(
      parentId: quarterFolderId,
      folderName: getMonthName(date),
    );
  }

  Future<DriveMonthFolders> ensureMonthStructure(DateTime date) async {
    final rootFolderId = await _requiredRootFolderId();
    final cacheKey = '$rootFolderId:${date.year}:${date.month}';
    final cached = _monthStructureCache[cacheKey];
    if (cached != null) return cached;

    final yearFolderId = await ensureYearFolder(
      rootFolderId: rootFolderId,
      year: date.year,
    );

    final quarterFolderId = await ensureQuarterFolder(
      yearFolderId: yearFolderId,
      date: date,
    );
    final monthFolderId = await ensureMonthFolder(
      quarterFolderId: quarterFolderId,
      date: date,
    );

    // Las dos no dependen la una de la otra.
    final subcarpetas = await Future.wait([
      ensureFolder(parentId: monthFolderId, folderName: carpetaFacturas),
      asegurarCarpetaGastos(monthFolderId),
    ]);

    final folders = DriveMonthFolders(
      yearFolderId: yearFolderId,
      quarterFolderId: quarterFolderId,
      monthFolderId: monthFolderId,
      facturasFolderId: subcarpetas[0],
      gastosInversionesFolderId: subcarpetas[1],
    );
    _monthStructureCache[cacheKey] = folders;
    return folders;
  }

  /// Deja montado el año entero en Drive.
  ///
  /// Los trimestres no dependen unos de otros, ni los meses dentro de un
  /// trimestre, así que van en paralelo con un tope de llamadas a la vez para
  /// no castigar la cuota de Drive. [alAvanzar] se llama cada vez que una
  /// carpeta queda lista, para poder enseñar el progreso.
  Future<void> createFullYearStructure(
    int year, {
    void Function(int hechas, int total)? alAvanzar,
  }) async {
    final total = cuentaCarpetas(arbolDeAno(year));
    var hechas = 0;
    void avanzar([int cuantas = 1]) {
      hechas += cuantas;
      alAvanzar?.call(hechas, total);
    }

    await exigirRaizUsable();
    final rootFolderId = await _requiredRootFolderId();
    final yearFolderId = await ensureYearFolder(
      rootFolderId: rootFolderId,
      year: year,
    );
    avanzar();
    await _deleteLegacyBackupFolder(yearFolderId);

    await ejecutarEnParalelo(
      [
        for (var trimestre = 0; trimestre < 4; trimestre++)
          () async {
            final primerMes = trimestre * 3 + 1;
            // Crear aquí el trimestre deja el id en caché, así que los
            // tres meses no se pisan buscándolo a la vez.
            await ensureQuarterFolder(
              yearFolderId: yearFolderId,
              date: DateTime(year, primerMes),
            );
            avanzar();

            await ejecutarEnParalelo([
              for (var mes = primerMes; mes < primerMes + 3; mes++)
                () async {
                  await ensureMonthStructure(DateTime(year, mes));
                  // El mes y sus dos carpetas.
                  avanzar(3);
                },
            ]);
          },
      ],
      // Los trimestres abren tres meses cada uno: con dos a la vez ya se
      // sostienen seis llamadas simultáneas.
      limite: 2,
    );
  }

  Future<DriveFolderResult> _createRootFolder(String name) async {
    final api = await _driveApi();
    final folder = drive.File()
      ..name = sanitizeDriveFileName(name)
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await api.files.create(
      folder,
      $fields: 'id,name,webViewLink',
    );
    final id = created.id;
    final folderName = created.name;
    if (id == null || folderName == null) {
      throw Exception('No se pudo crear la carpeta inicial en Google Drive.');
    }
    return DriveFolderResult(
      id: id,
      name: folderName,
      webViewLink: created.webViewLink,
    );
  }

  Future<void> _deleteLegacyBackupFolder(String yearFolderId) async {
    final api = await _driveApi();
    final result = await api.files.list(
      q:
          "trashed = false "
          "and mimeType = 'application/vnd.google-apps.folder' "
          "and '${_escapeQuery(yearFolderId)}' in parents "
          "and name = 'BACKUPS APP'",
      spaces: 'drive',
      $fields: 'files(id,name)',
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
    );
    final folders = result.files ?? const <drive.File>[];
    for (final folder in folders) {
      final id = folder.id;
      if (id == null || id.isEmpty) continue;
      try {
        await api.files.delete(id, supportsAllDrives: true);
      } catch (e) {
        debugPrint(
          '[Drive] No se pudo eliminar carpeta legacy BACKUPS APP: $e',
        );
      }
    }
  }

  Future<DriveUploadResult> uploadFile({
    required File file,
    required String fileName,
    required String parentFolderId,
    required String mimeType,
  }) async {
    final api = await _driveApi();
    final metadata = drive.File()
      ..name = sanitizeDriveFileName(fileName)
      ..parents = [parentFolderId];
    final media = drive.Media(
      file.openRead(),
      await file.length(),
      contentType: mimeType,
    );
    final result = await api.files.create(
      metadata,
      uploadMedia: media,
      $fields: 'id,webViewLink',
    );
    if (result.id == null) {
      throw Exception('No se pudo subir el archivo a Drive.');
    }
    return DriveUploadResult(fileId: result.id!, fileUrl: result.webViewLink);
  }

  Future<List<DriveBackupFile>> listBackupFiles({int limit = 50}) async {
    final api = await _driveApi();
    final result = await api.files.list(
      q:
          "trashed = false "
          "and mimeType = 'application/json' "
          "and name contains 'backup_misbolos_'",
      spaces: 'drive',
      orderBy: 'createdTime desc',
      pageSize: limit,
      $fields: 'files(id,name,createdTime,size)',
    );
    final files = result.files ?? const <drive.File>[];
    return files
        .where((f) => f.id != null && f.name != null)
        .map(
          (f) => DriveBackupFile(
            id: f.id!,
            name: f.name!,
            createdAt: f.createdTime,
            sizeBytes: f.size != null ? int.tryParse(f.size!) : null,
          ),
        )
        .toList();
  }

  Future<String> downloadTextFile(String fileId) async {
    final api = await _driveApi();
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (media is! drive.Media) {
      throw Exception('No se pudo descargar el archivo de Drive.');
    }
    final chunks = await media.stream.toList();
    final bytes = chunks.expand((c) => c).toList(growable: false);
    return String.fromCharCodes(bytes);
  }

  Future<DriveExistingFileResult?> findFileInFolderByName({
    required String parentFolderId,
    required String fileName,
  }) async {
    final api = await _driveApi();
    final normalizedName = sanitizeDriveFileName(fileName);
    final result = await api.files.list(
      q:
          "trashed = false "
          "and '${_escapeQuery(parentFolderId)}' in parents "
          "and name = '${_escapeQuery(normalizedName)}'",
      spaces: 'drive',
      $fields: 'files(id,webViewLink)',
      orderBy: 'createdTime desc',
      pageSize: 1,
      supportsAllDrives: true,
    );
    final files = result.files ?? const [];
    if (files.isEmpty || files.first.id == null) return null;
    return DriveExistingFileResult(
      fileId: files.first.id!,
      fileUrl: files.first.webViewLink,
    );
  }

  Future<void> trashFile(String fileId) async {
    final id = fileId.trim();
    if (id.isEmpty) return;
    final api = await _driveApi();
    await api.files.update(
      drive.File()..trashed = true,
      id,
      supportsAllDrives: true,
      $fields: 'id',
    );
  }

  Future<DriveUploadResult> updateFile({
    required String fileId,
    required File file,
    required String mimeType,
  }) async {
    final api = await _driveApi();
    final media = drive.Media(
      file.openRead(),
      await file.length(),
      contentType: mimeType,
    );
    final result = await api.files.update(
      drive.File(),
      fileId,
      uploadMedia: media,
      $fields: 'id,webViewLink',
    );
    if (result.id == null) {
      throw Exception('No se pudo actualizar el archivo en Drive.');
    }
    return DriveUploadResult(fileId: result.id!, fileUrl: result.webViewLink);
  }

  Future<DriveUploadResult> copyFileToFolder({
    required String sourceFileId,
    required String fileName,
    required String parentFolderId,
  }) async {
    final api = await _driveApi();
    final copied = await api.files.copy(
      drive.File()
        ..name = sanitizeDriveFileName(fileName)
        ..parents = [parentFolderId],
      sourceFileId,
      $fields: 'id,webViewLink',
      supportsAllDrives: true,
    );
    if (copied.id == null) {
      throw Exception('No se pudo copiar el archivo en Drive.');
    }
    return DriveUploadResult(fileId: copied.id!, fileUrl: copied.webViewLink);
  }

  /// Mueve el fichero a [targetFolderId] cambiando sus `parents`, sin copiarlo.
  Future<void> moveFileToFolder({
    required String fileId,
    required String targetFolderId,
  }) async {
    final api = await _driveApi();
    final current =
        await api.files.get(
              fileId,
              $fields: 'id,parents',
              supportsAllDrives: true,
            )
            as drive.File;
    final parents = (current.parents ?? []).whereType<String>().toList();
    if (parents.length == 1 && parents.first == targetFolderId) return;
    final toRemove = parents.where((id) => id != targetFolderId).join(',');
    await api.files.update(
      drive.File(),
      fileId,
      addParents: parents.contains(targetFolderId) ? null : targetFolderId,
      removeParents: toRemove.isEmpty ? null : toRemove,
      supportsAllDrives: true,
      $fields: 'id,parents',
    );
  }

  Future<void> openFolder(String folderId) async {
    final uri = Uri.parse('https://drive.google.com/drive/folders/$folderId');
    debugPrint('[DRIVE][ABRIR] $uri');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir la carpeta de Drive.');
    }
  }

  Future<File> downloadFileTo({
    required String fileId,
    required String targetPath,
  }) async {
    final api = await _driveApi();
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (media is! drive.Media) {
      throw Exception('No se pudo descargar el archivo de Drive.');
    }
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    return file;
  }

  Future<bool> fileExists(String fileId) async {
    final id = fileId.trim();
    if (id.isEmpty) return false;
    final api = await _driveApi();
    try {
      final file = await api.files.get(
        id,
        $fields: 'id',
        supportsAllDrives: true,
      );
      return (file as drive.File).id != null;
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('404') || message.contains('not found')) {
        return false;
      }
      rethrow;
    }
  }

  Future<bool> fileExistsUnderRoot({
    required String fileId,
    required String rootFolderId,
  }) async {
    final id = fileId.trim();
    final rootId = rootFolderId.trim();
    if (id.isEmpty || rootId.isEmpty) return false;
    final api = await _driveApi();
    try {
      final file =
          await api.files.get(
                id,
                $fields: 'id,parents,trashed',
                supportsAllDrives: true,
              )
              as drive.File;
      if (file.id == null || file.trashed == true) return false;
      final parents = (file.parents ?? []).whereType<String>().toList();
      if (parents.isEmpty) return false;
      if (parents.contains(rootId)) return true;
      final visited = <String>{id};
      return _parentsContainRoot(
        api: api,
        parents: parents,
        rootFolderId: rootId,
        visited: visited,
      );
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains('404') || message.contains('not found')) {
        return false;
      }
      rethrow;
    }
  }

  Future<bool> _parentsContainRoot({
    required drive.DriveApi api,
    required List<String> parents,
    required String rootFolderId,
    required Set<String> visited,
  }) async {
    for (final parentId in parents) {
      if (parentId == rootFolderId) return true;
      if (visited.contains(parentId)) continue;
      visited.add(parentId);
      try {
        final parent =
            await api.files.get(
                  parentId,
                  $fields: 'id,parents,trashed',
                  supportsAllDrives: true,
                )
                as drive.File;
        if (parent.id == null || parent.trashed == true) continue;
        final nextParents = (parent.parents ?? []).whereType<String>().toList();
        if (nextParents.contains(rootFolderId)) return true;
        if (nextParents.isEmpty) continue;
        final found = await _parentsContainRoot(
          api: api,
          parents: nextParents,
          rootFolderId: rootFolderId,
          visited: visited,
        );
        if (found) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Future<drive.DriveApi> _driveApi() async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      var token = await PlatformAuthService.instance.getAccessToken();
      if (token == null) {
        final signedIn = await PlatformAuthService.instance.signInSilently();
        if (signedIn) {
          token = await PlatformAuthService.instance.getAccessToken();
        }
      }
      if (token == null) {
        throw Exception('No hay sesión activa de Google Drive.');
      }
      final credentials = auth.AccessCredentials(
        auth.AccessToken(
          'Bearer',
          token,
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        null,
        [drive.DriveApi.driveScope],
      );
      return drive.DriveApi(
        auth.authenticatedClient(http.Client(), credentials),
      );
    }

    if (!kIsWeb && Platform.isMacOS) {
      var token = await PlatformAuthService.instance.getAccessToken();
      if (token != null && token.isNotEmpty) {
        final credentials = auth.AccessCredentials(
          auth.AccessToken(
            'Bearer',
            token,
            DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
          null,
          [drive.DriveApi.driveScope],
        );
        return drive.DriveApi(
          auth.authenticatedClient(http.Client(), credentials),
        );
      }
      await GoogleAuthService.instance.signInSilently();
    }

    if (!GoogleAuthService.instance.isSignedIn) {
      await GoogleAuthService.instance.signInSilently();
    }
    final client = await GoogleAuthService.instance.httpClient;
    return drive.DriveApi(client);
  }

  Future<String> _requiredRootFolderId() async {
    final settings = await _settingsRepository.get();
    final rootId = settings.driveRootFolderId;
    if (rootId == null || rootId.trim().isEmpty) {
      throw Exception(
        'Selecciona una carpeta de trabajo antes de sincronizar.',
      );
    }
    return rootId;
  }

  String _escapeQuery(String value) => value.replaceAll("'", r"\'");

  String _folderCacheKey(String parentId, String folderName) {
    return '$parentId::$folderName';
  }

  void _clearFolderCache() {
    _folderIdCache.clear();
    _monthStructureCache.clear();
  }

  Future<void> _persistDriveConnected(bool connected) async {
    final settings = await _settingsRepository.get();
    if (settings.driveConnected == connected) return;
    await _settingsRepository.save(
      settings.copyWith(driveConnected: connected),
    );
  }

  bool _looksLikePermissionError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('insufficient') ||
        message.contains('permission') ||
        message.contains('forbidden') ||
        message.contains('403') ||
        message.contains('scope');
  }

  void _logStatus(DriveConnectionCheck result) {
    debugPrint(
      '[DriveStatus] status=${result.status.name} message="${result.message}" '
      'folder=${result.folderId ?? '-'} account=${result.account?.email ?? '-'} '
      'error=${result.error ?? '-'}',
    );
  }
}

String sanitizeDriveFileName(String input) {
  final sanitized = input
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (sanitized.length <= 120) return sanitized;
  return sanitized.substring(0, 120).trim();
}
