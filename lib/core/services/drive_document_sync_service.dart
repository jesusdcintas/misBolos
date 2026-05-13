import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../database/database_helper.dart';
import '../../models/asset.dart';
import '../../models/client.dart';
import '../../models/expense.dart';
import '../../models/invoice.dart';
import '../../repositories/asset_repository.dart';
import '../../repositories/client_repository.dart';
import '../../repositories/expense_repository.dart';
import '../../repositories/invoice_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../services/pdf_service.dart';
import 'google_drive_service.dart';

class DriveDocumentSyncResult {
  final int invoicesUploaded;
  final int expensesUploaded;
  final int assetsUploaded;
  final int skipped;
  final int failed;

  const DriveDocumentSyncResult({
    this.invoicesUploaded = 0,
    this.expensesUploaded = 0,
    this.assetsUploaded = 0,
    this.skipped = 0,
    this.failed = 0,
  });

  int get uploaded => invoicesUploaded + expensesUploaded + assetsUploaded;

  DriveDocumentSyncResult copyWith({
    int? invoicesUploaded,
    int? expensesUploaded,
    int? assetsUploaded,
    int? skipped,
    int? failed,
  }) {
    return DriveDocumentSyncResult(
      invoicesUploaded: invoicesUploaded ?? this.invoicesUploaded,
      expensesUploaded: expensesUploaded ?? this.expensesUploaded,
      assetsUploaded: assetsUploaded ?? this.assetsUploaded,
      skipped: skipped ?? this.skipped,
      failed: failed ?? this.failed,
    );
  }
}

class DriveRetryResult {
  final int retried;
  final int succeeded;
  final int failed;
  final int skippedByMaxAttempts;
  final List<String> recentErrors;

  const DriveRetryResult({
    this.retried = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.skippedByMaxAttempts = 0,
    this.recentErrors = const [],
  });
}

class DriveDocumentSyncService {
  static final DriveDocumentSyncService instance = DriveDocumentSyncService._();
  DriveDocumentSyncService._();

  final GoogleDriveService _drive = GoogleDriveService.instance;
  final InvoiceRepository _invoiceRepository = InvoiceRepository.instance;
  final ExpenseRepository _expenseRepository = ExpenseRepository.instance;
  final AssetRepository _assetRepository = AssetRepository.instance;
  final ClientRepository _clientRepository = ClientRepository.instance;
  final SettingsRepository _settingsRepository = SettingsRepository();
  static const int maxRetryAttempts = 5;

  Future<DriveDocumentSyncResult> syncExistingDocuments() async {
    await _drive.ensureRootFolder();

    var result = const DriveDocumentSyncResult();

    final invoices = await _invoiceRepository.getAll();
    for (final baseInvoice in invoices) {
      final invoice = await _invoiceRepository.getById(baseInvoice.id);
      if (invoice == null) {
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      try {
        await _syncInvoice(invoice);
        result = result.copyWith(invoicesUploaded: result.invoicesUploaded + 1);
      } catch (e) {
        await _queueFailedSync(
          entityType: 'invoice',
          entityId: invoice.id,
          action: invoice.driveFileId == null ? 'upload' : 'update',
          targetFolderType: 'FACTURAS',
          lastError: e.toString(),
        );
        result = result.copyWith(failed: result.failed + 1);
      }
    }

    final expenses = await _expenseRepository.getAll();
    for (final expense in expenses) {
      if (expense.id == null || expense.documentoPath == null) {
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      try {
        await _syncExpense(expense);
        result = result.copyWith(expensesUploaded: result.expensesUploaded + 1);
      } catch (e) {
        await _queueFailedSync(
          entityType: 'expense',
          entityId: expense.id!.toString(),
          action: expense.driveFileId == null ? 'upload' : 'update',
          localFilePath: expense.documentoPath,
          targetFolderType: 'GASTOS',
          lastError: e.toString(),
        );
        result = result.copyWith(failed: result.failed + 1);
      }
    }

    final assets = await _assetRepository.getAll();
    for (final asset in assets) {
      if (asset.id == null || asset.documentoPath == null) {
        result = result.copyWith(skipped: result.skipped + 1);
        continue;
      }
      try {
        await _syncAsset(asset);
        result = result.copyWith(assetsUploaded: result.assetsUploaded + 1);
      } catch (e) {
        await _queueFailedSync(
          entityType: 'asset',
          entityId: asset.id!.toString(),
          action: asset.driveFileId == null ? 'upload' : 'update',
          localFilePath: asset.documentoPath,
          targetFolderType: 'INVERSIONES',
          lastError: e.toString(),
        );
        result = result.copyWith(failed: result.failed + 1);
      }
    }

    final settings = await _settingsRepository.get();
    await _settingsRepository.save(
      settings.copyWith(lastDriveSyncAt: DateTime.now()),
    );
    return result;
  }

  Future<void> _syncInvoice(Invoice invoice) async {
    final client = await _clientRepository.getById(invoice.clientId);
    final settings = await _settingsRepository.get();
    final file = await PdfService().generateInvoicePdf(
      invoice: invoice,
      client: client ?? _fallbackClient(),
      settings: settings,
    );
    final monthFolders = await _drive.ensureMonthStructure(invoice.fecha);
    final fileName = _invoiceFileName(
      invoice: invoice,
      clientName: client?.nombre,
    );
    final uploaded = await _uploadOrUpdate(
      existingFileId: invoice.driveFileId,
      file: file,
      fileName: fileName,
      parentFolderId: monthFolders.facturasFolderId,
      mimeType: 'application/pdf',
    );
    await _invoiceRepository.updateDriveMetadata(
      id: invoice.id,
      driveFileId: uploaded.fileId,
      driveFileUrl: uploaded.fileUrl,
      driveSyncedAt: DateTime.now(),
    );
  }

  Future<void> syncInvoiceById(String invoiceId) async {
    await _drive.ensureRootFolder();
    final invoice = await _invoiceRepository.getById(invoiceId);
    if (invoice == null) {
      throw Exception('Factura no encontrada para sincronizar.');
    }
    try {
      await _syncInvoice(invoice);
      final settings = await _settingsRepository.get();
      await _settingsRepository.save(
        settings.copyWith(lastDriveSyncAt: DateTime.now()),
      );
    } catch (e) {
      await _queueFailedSync(
        entityType: 'invoice',
        entityId: invoice.id,
        action: invoice.driveFileId == null ? 'upload' : 'update',
        targetFolderType: 'FACTURAS',
        lastError: e.toString(),
      );
      rethrow;
    }
  }

  Future<int> getPendingQueueCount() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM drive_sync_queue
      WHERE attempts < ?
      ''',
      [maxRetryAttempts],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<List<Map<String, Object?>>> getRecentQueueErrors({
    int limit = 5,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'drive_sync_queue',
      columns: ['entity_type', 'entity_id', 'attempts', 'last_error'],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
  }

  Future<DriveRetryResult> retryPendingDriveSync() async {
    await _drive.ensureRootFolder();
    final db = await DatabaseHelper.instance.database;
    final queue = await db.query(
      'drive_sync_queue',
      where: 'attempts < ?',
      whereArgs: [maxRetryAttempts],
      orderBy: 'created_at ASC',
      limit: 200,
    );
    if (queue.isEmpty) {
      return const DriveRetryResult();
    }

    var retried = 0;
    var succeeded = 0;
    var failed = 0;
    var skippedByMaxAttempts = 0;
    final errors = <String>[];

    for (final item in queue) {
      retried++;
      final id = item['id'] as String;
      final entityType = (item['entity_type'] as String?) ?? '';
      final entityId = (item['entity_id'] as String?) ?? '';
      final attempts = (item['attempts'] as int?) ?? 0;

      try {
        if (entityType == 'invoice') {
          final invoice = await _invoiceRepository.getById(entityId);
          if (invoice == null) {
            throw Exception('Factura $entityId no encontrada.');
          }
          await _syncInvoice(invoice);
        } else if (entityType == 'expense') {
          final expenseId = int.tryParse(entityId);
          if (expenseId == null) {
            throw Exception('Expense id inválido.');
          }
          final expense = await _expenseRepository.getById(expenseId);
          if (expense == null) {
            throw Exception('Gasto $entityId no encontrado.');
          }
          await _syncExpense(expense);
        } else if (entityType == 'asset') {
          final assetId = int.tryParse(entityId);
          if (assetId == null) {
            throw Exception('Asset id inválido.');
          }
          final asset = await _assetRepository.getById(assetId);
          if (asset == null) {
            throw Exception('Inversión $entityId no encontrada.');
          }
          await _syncAsset(asset);
        } else if (entityType == 'backup') {
          throw Exception(
            'Los backups pendientes se recrean desde "Crear backup ahora".',
          );
        } else {
          throw Exception('Tipo de entidad no soportado: $entityType');
        }

        await db.delete('drive_sync_queue', where: 'id = ?', whereArgs: [id]);
        succeeded++;
      } catch (error) {
        final nextAttempts = attempts + 1;
        await db.update(
          'drive_sync_queue',
          {
            'attempts': nextAttempts,
            'last_error': error.toString(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        failed++;
        if (errors.length < 5) {
          errors.add('$entityType/$entityId: $error');
        }
        if (nextAttempts >= maxRetryAttempts) {
          skippedByMaxAttempts++;
        }
      }
    }

    if (succeeded > 0) {
      final settings = await _settingsRepository.get();
      await _settingsRepository.save(
        settings.copyWith(lastDriveSyncAt: DateTime.now()),
      );
    }

    return DriveRetryResult(
      retried: retried,
      succeeded: succeeded,
      failed: failed,
      skippedByMaxAttempts: skippedByMaxAttempts,
      recentErrors: errors,
    );
  }

  Future<void> _syncExpense(Expense expense) async {
    final file = await _existingFile(expense.documentoPath!);
    final monthFolders = await _drive.ensureMonthStructure(expense.fecha);
    final uploaded = await _uploadOrUpdate(
      existingFileId: expense.driveFileId,
      file: file,
      fileName: _expenseFileName(expense, file),
      parentFolderId: monthFolders.gastosFolderId,
      mimeType: _mimeTypeFor(file.path),
    );
    await _expenseRepository.updateDriveMetadata(
      id: expense.id!,
      driveFileId: uploaded.fileId,
      driveFileUrl: uploaded.fileUrl,
      driveSyncedAt: DateTime.now(),
    );
  }

  Future<void> _syncAsset(Asset asset) async {
    final file = await _existingFile(asset.documentoPath!);
    final monthFolders = await _drive.ensureMonthStructure(asset.fechaCompra);
    final uploaded = await _uploadOrUpdate(
      existingFileId: asset.driveFileId,
      file: file,
      fileName: _assetFileName(asset, file),
      parentFolderId: monthFolders.inversionesFolderId,
      mimeType: _mimeTypeFor(file.path),
    );
    await _assetRepository.updateDriveMetadata(
      id: asset.id!,
      driveFileId: uploaded.fileId,
      driveFileUrl: uploaded.fileUrl,
      driveSyncedAt: DateTime.now(),
    );
  }

  Future<DriveUploadResult> _uploadOrUpdate({
    required String? existingFileId,
    required File file,
    required String fileName,
    required String parentFolderId,
    required String mimeType,
  }) {
    if (existingFileId != null && existingFileId.isNotEmpty) {
      return _drive.updateFile(
        fileId: existingFileId,
        file: file,
        mimeType: mimeType,
      );
    }
    return _drive.uploadFile(
      file: file,
      fileName: fileName,
      parentFolderId: parentFolderId,
      mimeType: mimeType,
    );
  }

  Future<File> _existingFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('No existe el archivo local: $path');
    }
    return file;
  }

  String _invoiceFileName({
    required Invoice invoice,
    required String? clientName,
  }) {
    final number = invoice.numero.toString().padLeft(3, '0');
    final date = _dateFormat.format(invoice.fecha);
    return sanitizeDriveFileName(
      'FACTURA $number - ${clientName ?? 'Sin cliente'} - $date.pdf',
    );
  }

  String _expenseFileName(Expense expense, File file) {
    final date = _dateFormat.format(expense.fecha);
    final provider = expense.proveedor?.trim().isNotEmpty == true
        ? expense.proveedor!.trim()
        : 'Sin proveedor';
    final amount = _moneyFormat.format(expense.total);
    return sanitizeDriveFileName(
      '$date - ${expense.concepto} - $provider - $amount${_extension(file)}',
    );
  }

  String _assetFileName(Asset asset, File file) {
    final date = _dateFormat.format(asset.fechaCompra);
    final amount = _moneyFormat.format(
      asset.importeConIva > 0 ? asset.importeConIva : asset.importeTotal,
    );
    return sanitizeDriveFileName(
      '$date - ${asset.descripcion} - $amount${_extension(file)}',
    );
  }

  String _extension(File file) {
    final ext = p.extension(file.path).toLowerCase();
    return ext.isEmpty ? '' : ext;
  }

  String _mimeTypeFor(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _queueFailedSync({
    required String entityType,
    required String entityId,
    required String action,
    required String targetFolderType,
    required String lastError,
    String? localFilePath,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'drive_sync_queue',
      where: 'entity_type = ? AND entity_id = ? AND action = ?',
      whereArgs: [entityType, entityId, action],
      limit: 1,
    );
    final now = DateTime.now().toIso8601String();
    if (existing.isEmpty) {
      await db.insert('drive_sync_queue', {
        'id': const Uuid().v4(),
        'entity_type': entityType,
        'entity_id': entityId,
        'action': action,
        'local_file_path': localFilePath,
        'target_folder_type': targetFolderType,
        'attempts': 1,
        'last_error': lastError,
        'created_at': now,
        'updated_at': now,
      });
      return;
    }
    final current = existing.first;
    final currentAttempts = (current['attempts'] as int?) ?? 0;
    await db.update(
      'drive_sync_queue',
      {
        'local_file_path': localFilePath ?? current['local_file_path'],
        'target_folder_type': targetFolderType,
        'attempts': currentAttempts + 1,
        'last_error': lastError,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [current['id']],
    );
  }

  Client _fallbackClient() => Client(nombre: 'Sin cliente');

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  static final NumberFormat _moneyFormat = NumberFormat('#,##0.00', 'es_ES');
}
