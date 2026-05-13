import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../models/app_settings.dart';
import '../../repositories/asset_repository.dart';
import '../../repositories/client_repository.dart';
import '../../repositories/expense_repository.dart';
import '../../repositories/gig_repository.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/settings_repository.dart';
import 'google_drive_service.dart';

class DriveBackupResult {
  final String fileId;
  final String? fileUrl;
  final String fileName;

  const DriveBackupResult({
    required this.fileId,
    required this.fileUrl,
    required this.fileName,
  });
}

class DriveBackupService {
  static final DriveBackupService instance = DriveBackupService._();
  DriveBackupService._();

  final GoogleDriveService _drive = GoogleDriveService.instance;
  final SettingsRepository _settingsRepository = SettingsRepository();
  final ClientRepository _clientRepository = ClientRepository.instance;
  final GigRepository _gigRepository = GigRepository.instance;
  final InvoiceRepository _invoiceRepository = InvoiceRepository.instance;
  final ExpenseRepository _expenseRepository = ExpenseRepository.instance;
  final AssetRepository _assetRepository = AssetRepository.instance;

  Future<DriveBackupResult> createBackupNow() async {
    await _drive.ensureRootFolder();

    final now = DateTime.now();
    final backupData = await _buildBackupPayload(now);
    final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
    final tempDir = await getTemporaryDirectory();
    final fileName = _backupFileName(now);
    final backupFile = File('${tempDir.path}/$fileName');
    await backupFile.writeAsString(jsonString);

    try {
      final rootFolderId = await _drive.ensureRootFolder();
      final yearFolderId = await _drive.ensureYearFolder(
        rootFolderId: rootFolderId,
        year: now.year,
      );
      final backupsFolderId = await _drive.ensureFolder(
        parentId: yearFolderId,
        folderName: 'BACKUPS APP',
      );
      final uploaded = await _drive.uploadFile(
        file: backupFile,
        fileName: fileName,
        parentFolderId: backupsFolderId,
        mimeType: 'application/json',
      );

      final settings = await _settingsRepository.get();
      await _settingsRepository.save(
        settings.copyWith(lastDriveBackupAt: DateTime.now()),
      );

      return DriveBackupResult(
        fileId: uploaded.fileId,
        fileUrl: uploaded.fileUrl,
        fileName: fileName,
      );
    } catch (error) {
      await _queueFailedBackup(
        localFilePath: backupFile.path,
        lastError: error.toString(),
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _buildBackupPayload(DateTime now) async {
    final clients = await _clientRepository.getAll();
    final gigs = await _gigRepository.getAll();
    final invoices = await _invoiceRepository.getAll();
    final expenses = await _expenseRepository.getAll();
    final assets = await _assetRepository.getAll();
    final settings = await _settingsRepository.get();

    final officialGigs = gigs.where((gig) => gig.facturable).toList();

    return {
      'backup_version': '1.0.0',
      'schema_version': 1,
      'created_at': now.toIso8601String(),
      'source': 'misbolos',
      'privacy': {
        'includes_private_b_docs': false,
        'notes':
            'No se suben documentos de bolos B por defecto. Este backup contiene datos de negocio y referencias de Drive.',
      },
      'counts': {
        'clientes': clients.length,
        'bolos_oficiales': officialGigs.length,
        'facturas': invoices.length,
        'gastos': expenses.length,
        'inversiones': assets.length,
      },
      'fiscal_settings': _fiscalSettings(settings),
      'clientes': clients.map((client) => client.toMap()).toList(),
      'bolos_oficiales': officialGigs.map((gig) => gig.toMap()).toList(),
      'facturas': invoices.map((invoice) => invoice.toMap()).toList(),
      'gastos': expenses.map((expense) => expense.toMap()).toList(),
      'inversiones': assets.map((asset) => asset.toMap()).toList(),
    };
  }

  Map<String, dynamic> _fiscalSettings(AppSettings settings) {
    return {
      'emisor_nombre': settings.emisorNombre,
      'emisor_nif': settings.emisorNIF,
      'emisor_direccion': settings.emisorDireccion,
      'emisor_ciudad': settings.emisorCiudad,
      'emisor_provincia': settings.emisorProvincia,
      'emisor_codigo_postal': settings.emisorCodigoPostal,
      'emisor_email': settings.emisorEmail,
      'emisor_telefono': settings.emisorTelefono,
      'iban': settings.iban,
      'iva_default': settings.ivaDefault,
    };
  }

  String _backupFileName(DateTime now) {
    final date = '${now.year}-${_two(now.month)}-${_two(now.day)}';
    final time = '${_two(now.hour)}-${_two(now.minute)}';
    return sanitizeDriveFileName('backup_misbolos_${date}_$time.json');
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  Future<void> _queueFailedBackup({
    required String localFilePath,
    required String lastError,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('drive_sync_queue', {
      'id': const Uuid().v4(),
      'entity_type': 'backup',
      'entity_id': now,
      'action': 'upload',
      'local_file_path': localFilePath,
      'target_folder_type': 'BACKUPS APP',
      'attempts': 1,
      'last_error': lastError,
      'created_at': now,
      'updated_at': now,
    });
  }
}
