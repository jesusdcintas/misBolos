import 'dart:convert';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path_provider/path_provider.dart';
import '../database/database_helper.dart';
import 'google_auth_service.dart';

class GoogleDriveService {
  drive.DriveApi? get _driveApi => GoogleAuthService.instance.driveApi;

  bool get isConnected => _driveApi != null;

  /// Obtiene o crea la carpeta "MisBolos" en Drive
  Future<String> _ensureFolder(String name, {String? parentId}) async {
    final api = _driveApi!;

    final query = StringBuffer("mimeType='application/vnd.google-apps.folder' and name='$name' and trashed=false");
    if (parentId != null) {
      query.write(" and '$parentId' in parents");
    }

    final result = await api.files.list(q: query.toString(), spaces: 'drive');
    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';
    if (parentId != null) {
      folder.parents = [parentId];
    }

    final created = await api.files.create(folder);
    return created.id!;
  }

  /// Backup completo de todos los datos (incluidos bolos en B)
  Future<void> backupDatabase() async {
    if (_driveApi == null) return;

    final db = await DatabaseHelper.instance.database;

    // Exportar todos los datos
    final clients = await db.query('clients');
    final gigs = await db.query('gigs');
    final invoices = await db.query('invoices');
    final settings = await db.query('app_settings');

    final backup = jsonEncode({
      'timestamp': DateTime.now().toIso8601String(),
      'clients': clients,
      'gigs': gigs,
      'invoices': invoices,
      'settings': settings,
    });

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/misbolos_backup.json');
    await file.writeAsString(backup);

    final rootFolderId = await _ensureFolder('MisBolos');
    final backupFolderId = await _ensureFolder('Backups', parentId: rootFolderId);

    final media = drive.Media(file.openRead(), file.lengthSync());
    final driveFile = drive.File()
      ..name = 'misbolos_backup_${DateTime.now().millisecondsSinceEpoch}.json'
      ..parents = [backupFolderId];

    await _driveApi!.files.create(driveFile, uploadMedia: media);
    await file.delete();
  }

  /// Sube un PDF de factura a Drive/MisBolos/Facturas
  Future<String?> uploadInvoicePdf(File pdfFile, String invoiceName) async {
    if (_driveApi == null) return null;

    final rootFolderId = await _ensureFolder('MisBolos');
    final facturasFolderId = await _ensureFolder('Facturas', parentId: rootFolderId);

    final media = drive.Media(pdfFile.openRead(), pdfFile.lengthSync());
    final driveFile = drive.File()
      ..name = '$invoiceName.pdf'
      ..parents = [facturasFolderId];

    final created = await _driveApi!.files.create(driveFile, uploadMedia: media);
    return created.id;
  }
}
