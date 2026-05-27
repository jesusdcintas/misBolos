import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
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

class DriveRestoreSummary {
  final int clientsInserted;
  final int clientsUpdated;
  final int gigsInserted;
  final int gigsUpdated;
  final int invoicesInserted;
  final int invoicesUpdated;
  final int expensesInserted;
  final int expensesUpdated;
  final int assetsInserted;
  final int assetsUpdated;
  final int skippedByConflict;
  final String localSnapshotPath;

  const DriveRestoreSummary({
    this.clientsInserted = 0,
    this.clientsUpdated = 0,
    this.gigsInserted = 0,
    this.gigsUpdated = 0,
    this.invoicesInserted = 0,
    this.invoicesUpdated = 0,
    this.expensesInserted = 0,
    this.expensesUpdated = 0,
    this.assetsInserted = 0,
    this.assetsUpdated = 0,
    this.skippedByConflict = 0,
    required this.localSnapshotPath,
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

  Future<List<DriveBackupFile>> listBackups({int limit = 50}) {
    return _drive.listBackupFiles(limit: limit);
  }

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

  Future<DriveRestoreSummary> restoreBackupNonDestructive({
    required DriveBackupFile backup,
  }) async {
    await _drive.ensureRootFolder();
    final raw = await _drive.downloadTextFile(backup.id);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Formato de backup inválido.');
    }
    final localSnapshotPath = await _writeLocalSnapshotBeforeRestore();
    final db = await DatabaseHelper.instance.database;

    var summary = DriveRestoreSummary(localSnapshotPath: localSnapshotPath);

    await db.transaction((txn) async {
      final clients = _asMapList(decoded['clientes']);
      for (final m in clients) {
        final local = await _getById(txn, 'clients', 'id', m['id']);
        if (local == null) {
          await txn.insert(
            'clients',
            _safeMapForInsert(m),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          summary = DriveRestoreSummary(
            localSnapshotPath: summary.localSnapshotPath,
            clientsInserted: summary.clientsInserted + 1,
            clientsUpdated: summary.clientsUpdated,
            gigsInserted: summary.gigsInserted,
            gigsUpdated: summary.gigsUpdated,
            invoicesInserted: summary.invoicesInserted,
            invoicesUpdated: summary.invoicesUpdated,
            expensesInserted: summary.expensesInserted,
            expensesUpdated: summary.expensesUpdated,
            assetsInserted: summary.assetsInserted,
            assetsUpdated: summary.assetsUpdated,
            skippedByConflict: summary.skippedByConflict,
          );
          continue;
        }
        if (_remoteIsNewer(m, local, fallbackToCreatedAt: false)) {
          await txn.update(
            'clients',
            _safeMapForUpdate(m),
            where: 'id = ?',
            whereArgs: [m['id']],
          );
          summary = DriveRestoreSummary(
            localSnapshotPath: summary.localSnapshotPath,
            clientsInserted: summary.clientsInserted,
            clientsUpdated: summary.clientsUpdated + 1,
            gigsInserted: summary.gigsInserted,
            gigsUpdated: summary.gigsUpdated,
            invoicesInserted: summary.invoicesInserted,
            invoicesUpdated: summary.invoicesUpdated,
            expensesInserted: summary.expensesInserted,
            expensesUpdated: summary.expensesUpdated,
            assetsInserted: summary.assetsInserted,
            assetsUpdated: summary.assetsUpdated,
            skippedByConflict: summary.skippedByConflict,
          );
        } else {
          summary = _incrementSkipped(summary);
        }
      }

      final gigs = _asMapList(decoded['bolos_oficiales']);
      for (final m in gigs) {
        final local = await _getById(txn, 'gigs', 'id', m['id']);
        if (local == null) {
          await txn.insert(
            'gigs',
            _safeMapForInsert(m),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          summary = _withCounts(summary, gigsInserted: 1);
          continue;
        }
        if (_remoteIsNewer(m, local)) {
          await txn.update(
            'gigs',
            _safeMapForUpdate(m),
            where: 'id = ?',
            whereArgs: [m['id']],
          );
          summary = _withCounts(summary, gigsUpdated: 1);
        } else {
          summary = _incrementSkipped(summary);
        }
      }

      final invoices = _asMapList(decoded['facturas']);
      for (final m in invoices) {
        final local = await _getById(txn, 'invoices', 'id', m['id']);
        if (local == null) {
          await txn.insert(
            'invoices',
            _safeMapForInsert(m),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          summary = _withCounts(summary, invoicesInserted: 1);
          continue;
        }
        if (_remoteIsNewer(m, local)) {
          await txn.update(
            'invoices',
            _safeMapForUpdate(m),
            where: 'id = ?',
            whereArgs: [m['id']],
          );
          summary = _withCounts(summary, invoicesUpdated: 1);
        } else {
          summary = _incrementSkipped(summary);
        }
      }

      final expenses = _asMapList(decoded['gastos']);
      for (final m in expenses) {
        final local = await _findLocalExpenseForRestore(txn, m);
        if (local == null) {
          await txn.insert(
            'expenses',
            _safeMapForInsert(m),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          summary = _withCounts(summary, expensesInserted: 1);
          continue;
        }
        if (_remoteIsNewer(m, local, fallbackToCreatedAt: true)) {
          await _updateExpenseForRestore(txn, m, local);
          summary = _withCounts(summary, expensesUpdated: 1);
        } else {
          summary = _incrementSkipped(summary);
        }
      }

      final assets = _asMapList(decoded['inversiones']);
      for (final m in assets) {
        final local = await _findLocalAssetForRestore(txn, m);
        if (local == null) {
          await txn.insert(
            'assets',
            _safeMapForInsert(m),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          summary = _withCounts(summary, assetsInserted: 1);
          continue;
        }
        if (_remoteIsNewer(m, local, fallbackToCreatedAt: true)) {
          await _updateAssetForRestore(txn, m, local);
          summary = _withCounts(summary, assetsUpdated: 1);
        } else {
          summary = _incrementSkipped(summary);
        }
      }
    });

    debugPrint(
      '[DRIVE][RESTORE] backup=${backup.name} inserted='
      '${summary.clientsInserted + summary.gigsInserted + summary.invoicesInserted + summary.expensesInserted + summary.assetsInserted} '
      'updated=${summary.clientsUpdated + summary.gigsUpdated + summary.invoicesUpdated + summary.expensesUpdated + summary.assetsUpdated} '
      'skipped=${summary.skippedByConflict}',
    );
    return summary;
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

  Future<String> _writeLocalSnapshotBeforeRestore() async {
    final now = DateTime.now();
    final payload = await _buildBackupPayload(now);
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(
      '${docsDir.path}/pre_restore_snapshot_${now.toIso8601String().replaceAll(':', '-')}.json',
    );
    await file.writeAsString(json);
    return file.path;
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, Object?>?> _getById(
    DatabaseExecutor db,
    String table,
    String column,
    Object? value,
  ) async {
    final rows = await db.query(
      table,
      where: '$column = ?',
      whereArgs: [value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, Object?>?> _findLocalExpenseForRestore(
    DatabaseExecutor db,
    Map<String, dynamic> remote,
  ) async {
    final cloudId = remote['cloud_id']?.toString();
    if (cloudId != null && cloudId.isNotEmpty) {
      final byCloud = await _getById(db, 'expenses', 'cloud_id', cloudId);
      if (byCloud != null) return byCloud;
    }
    final id = remote['id'];
    if (id != null) {
      return _getById(db, 'expenses', 'id', id);
    }
    return null;
  }

  Future<void> _updateExpenseForRestore(
    DatabaseExecutor db,
    Map<String, dynamic> remote,
    Map<String, Object?> local,
  ) async {
    final values = _safeMapForUpdate(remote);
    final localCloudId = local['cloud_id']?.toString();
    if (localCloudId != null && localCloudId.isNotEmpty) {
      await db.update(
        'expenses',
        values,
        where: 'cloud_id = ?',
        whereArgs: [localCloudId],
      );
      return;
    }
    final localId = local['id'];
    await db.update('expenses', values, where: 'id = ?', whereArgs: [localId]);
  }

  Future<Map<String, Object?>?> _findLocalAssetForRestore(
    DatabaseExecutor db,
    Map<String, dynamic> remote,
  ) async {
    final cloudId = remote['cloud_id']?.toString();
    if (cloudId != null && cloudId.isNotEmpty) {
      final byCloud = await _getById(db, 'assets', 'cloud_id', cloudId);
      if (byCloud != null) return byCloud;
    }
    final id = remote['id'];
    if (id != null) {
      return _getById(db, 'assets', 'id', id);
    }
    return null;
  }

  Future<void> _updateAssetForRestore(
    DatabaseExecutor db,
    Map<String, dynamic> remote,
    Map<String, Object?> local,
  ) async {
    final values = _safeMapForUpdate(remote);
    final localCloudId = local['cloud_id']?.toString();
    if (localCloudId != null && localCloudId.isNotEmpty) {
      await db.update(
        'assets',
        values,
        where: 'cloud_id = ?',
        whereArgs: [localCloudId],
      );
      return;
    }
    final localId = local['id'];
    await db.update('assets', values, where: 'id = ?', whereArgs: [localId]);
  }

  bool _remoteIsNewer(
    Map<String, dynamic> remote,
    Map<String, Object?> local, {
    bool fallbackToCreatedAt = false,
  }) {
    final remoteUpdated = _parseDate(remote['updated_at']);
    final localUpdated = _parseDate(local['updated_at']);
    if (remoteUpdated != null && localUpdated != null) {
      return remoteUpdated.isAfter(localUpdated);
    }
    if (fallbackToCreatedAt) {
      final remoteCreated = _parseDate(remote['created_at']);
      final localCreated = _parseDate(local['created_at']);
      if (remoteCreated != null && localCreated != null) {
        return remoteCreated.isAfter(localCreated);
      }
    }
    return false;
  }

  DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Map<String, Object?> _safeMapForInsert(Map<String, dynamic> input) {
    return Map<String, Object?>.from(input);
  }

  Map<String, Object?> _safeMapForUpdate(Map<String, dynamic> input) {
    final map = Map<String, Object?>.from(input);
    map.remove('id');
    return map;
  }

  DriveRestoreSummary _withCounts(
    DriveRestoreSummary s, {
    int clientsInserted = 0,
    int clientsUpdated = 0,
    int gigsInserted = 0,
    int gigsUpdated = 0,
    int invoicesInserted = 0,
    int invoicesUpdated = 0,
    int expensesInserted = 0,
    int expensesUpdated = 0,
    int assetsInserted = 0,
    int assetsUpdated = 0,
  }) {
    return DriveRestoreSummary(
      localSnapshotPath: s.localSnapshotPath,
      clientsInserted: s.clientsInserted + clientsInserted,
      clientsUpdated: s.clientsUpdated + clientsUpdated,
      gigsInserted: s.gigsInserted + gigsInserted,
      gigsUpdated: s.gigsUpdated + gigsUpdated,
      invoicesInserted: s.invoicesInserted + invoicesInserted,
      invoicesUpdated: s.invoicesUpdated + invoicesUpdated,
      expensesInserted: s.expensesInserted + expensesInserted,
      expensesUpdated: s.expensesUpdated + expensesUpdated,
      assetsInserted: s.assetsInserted + assetsInserted,
      assetsUpdated: s.assetsUpdated + assetsUpdated,
      skippedByConflict: s.skippedByConflict,
    );
  }

  DriveRestoreSummary _incrementSkipped(DriveRestoreSummary s) {
    return DriveRestoreSummary(
      localSnapshotPath: s.localSnapshotPath,
      clientsInserted: s.clientsInserted,
      clientsUpdated: s.clientsUpdated,
      gigsInserted: s.gigsInserted,
      gigsUpdated: s.gigsUpdated,
      invoicesInserted: s.invoicesInserted,
      invoicesUpdated: s.invoicesUpdated,
      expensesInserted: s.expensesInserted,
      expensesUpdated: s.expensesUpdated,
      assetsInserted: s.assetsInserted,
      assetsUpdated: s.assetsUpdated,
      skippedByConflict: s.skippedByConflict + 1,
    );
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
      'irpf_default': settings.irpfDefault,
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
