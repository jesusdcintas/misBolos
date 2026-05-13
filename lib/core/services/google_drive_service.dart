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

class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._();
  GoogleDriveService._();

  final SettingsRepository _settingsRepository = SettingsRepository();

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
      ),
    );
  }

  Future<void> signOut() async {
    if (_isMobile) {
      await PlatformAuthService.instance.signOut();
    } else {
      await GoogleAuthService.instance.signOut();
    }

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
    final settings = await _settingsRepository.get();
    final account = await getCurrentAccount();
    await _settingsRepository.save(
      settings.copyWith(
        driveConnected: true,
        driveRootFolderId: folder.id,
        driveRootFolderName: folder.name,
        driveAccountEmail: account?.email ?? settings.driveAccountEmail,
      ),
    );
  }

  Future<String> ensureRootFolder() {
    return _requiredRootFolderId();
  }

  Future<String> ensureFolder({
    required String parentId,
    required String folderName,
  }) async {
    final api = await _driveApi();
    final existing = await api.files.list(
      q:
          "mimeType = 'application/vnd.google-apps.folder' "
          "and trashed = false "
          "and '${_escapeQuery(parentId)}' in parents "
          "and name = '${_escapeQuery(folderName)}'",
      spaces: 'drive',
      $fields: 'files(id,name)',
      pageSize: 10,
    );

    final files = existing.files ?? [];
    if (files.isNotEmpty && files.first.id != null) {
      return files.first.id!;
    }

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentId];

    final created = await api.files.create(folder, $fields: 'id');
    final id = created.id;
    if (id == null) {
      throw Exception('Google Drive no devolvió ID para $folderName.');
    }
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

    return DriveMonthFolders(
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

  Future<void> openFolder(String folderId) async {
    final uri = Uri.parse('https://drive.google.com/drive/folders/$folderId');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir la carpeta de Drive.');
    }
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
