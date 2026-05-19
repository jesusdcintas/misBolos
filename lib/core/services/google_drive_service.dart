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
  final String gastosFolderId;
  final String inversionesFolderId;

  const DriveMonthFolders({
    required this.yearFolderId,
    required this.quarterFolderId,
    required this.monthFolderId,
    required this.facturasFolderId,
    required this.gastosFolderId,
    required this.inversionesFolderId,
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

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._();
  GoogleDriveService._();

  final SettingsRepository _settingsRepository = SettingsRepository();
  final Map<String, String> _folderIdCache = {};
  final Map<String, DriveMonthFolders> _monthStructureCache = {};

  bool get _isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> signIn() async {
    final success = _isMobile
        ? await PlatformAuthService.instance.signIn()
        : await GoogleAuthService.instance.signIn();

    if (!success) {
      throw Exception('No se pudo conectar con Google Drive.');
    }

    final settings = await _settingsRepository.get();
    final account = await getCurrentAccount();
    await _settingsRepository.save(
      settings.copyWith(
        driveConnected: true,
        driveAccountEmail: account?.email,
        driveAccountName: account?.displayName,
      ),
    );
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
    final settings = await _settingsRepository.get();
    return settings.driveConnected;
  }

  Future<GoogleAccount?> getCurrentAccount() async {
    if (_isMobile) {
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
        driveConnected: true,
        driveRootFolderId: folder.id,
        driveRootFolderName: folder.name,
        driveAccountEmail: account?.email ?? settings.driveAccountEmail,
        driveAccountName: account?.displayName ?? settings.driveAccountName,
      ),
    );
  }

  Future<bool> restoreSilently() async {
    final settings = await _settingsRepository.get();
    if ((settings.driveRootFolderId ?? '').isEmpty) return false;

    final success = _isMobile
        ? await PlatformAuthService.instance.signInSilently()
        : await GoogleAuthService.instance.signInSilently();
    if (!success) {
      return false;
    }

    final account = await getCurrentAccount();
    await _settingsRepository.save(
      settings.copyWith(
        driveConnected: true,
        driveAccountEmail: account?.email ?? settings.driveAccountEmail,
        driveAccountName: account?.displayName ?? settings.driveAccountName,
      ),
    );
    return true;
  }

  Future<String> ensureRootFolder() {
    return _requiredRootFolderId();
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
  }) async {
    final quarterId = await ensureFolder(
      parentId: yearFolderId,
      folderName: getQuarterName(date),
    );
    await ensureFolder(parentId: quarterId, folderName: 'MODELOS');
    return quarterId;
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
    await ensureFolder(parentId: yearFolderId, folderName: 'BACKUPS APP');

    final quarterFolderId = await ensureQuarterFolder(
      yearFolderId: yearFolderId,
      date: date,
    );
    final monthFolderId = await ensureMonthFolder(
      quarterFolderId: quarterFolderId,
      date: date,
    );

    final folders = DriveMonthFolders(
      yearFolderId: yearFolderId,
      quarterFolderId: quarterFolderId,
      monthFolderId: monthFolderId,
      facturasFolderId: await ensureFolder(
        parentId: monthFolderId,
        folderName: 'FACTURAS',
      ),
      gastosFolderId: await ensureFolder(
        parentId: monthFolderId,
        folderName: 'GASTOS',
      ),
      inversionesFolderId: await ensureFolder(
        parentId: monthFolderId,
        folderName: 'INVERSIONES',
      ),
    );
    _monthStructureCache[cacheKey] = folders;
    return folders;
  }

  Future<void> createFullYearStructure(int year) async {
    final rootFolderId = await _requiredRootFolderId();
    final yearFolderId = await ensureYearFolder(
      rootFolderId: rootFolderId,
      year: year,
    );
    await ensureFolder(parentId: yearFolderId, folderName: 'BACKUPS APP');

    for (var month = 1; month <= 12; month++) {
      await ensureMonthStructure(DateTime(year, month));
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

  Future<void> openFolder(String folderId) async {
    final uri = Uri.parse('https://drive.google.com/drive/folders/$folderId');
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
    if (_isMobile) {
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
}

String getQuarterName(DateTime date) {
  if (date.month <= 3) return '1 TRIMESTRE';
  if (date.month <= 6) return '2 TRIMESTRE';
  if (date.month <= 9) return '3 TRIMESTRE';
  return '4 TRIMESTRE';
}

String getMonthName(DateTime date) {
  const months = [
    'ENERO',
    'FEBRERO',
    'MARZO',
    'ABRIL',
    'MAYO',
    'JUNIO',
    'JULIO',
    'AGOSTO',
    'SEPTIEMBRE',
    'OCTUBRE',
    'NOVIEMBRE',
    'DICIEMBRE',
  ];
  return months[date.month - 1];
}

String getYearFolderName(DateTime date) => 'Contabilidad ${date.year}';

String sanitizeDriveFileName(String input) {
  final sanitized = input
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (sanitized.length <= 120) return sanitized;
  return sanitized.substring(0, 120).trim();
}
