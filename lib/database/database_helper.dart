import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'migrations/v1_initial.dart';
import 'migrations/v2_add_provincia_cp.dart';
import 'migrations/v3_add_client_provincia_alias.dart';
import 'migrations/v4_add_irpf.dart';
import 'migrations/v5_add_logo_size.dart';
import 'migrations/v6_add_pdf_theme.dart';
import 'migrations/v7_pending_deletions.dart';
import 'migrations/v8_add_client_aliases.dart';
import 'migrations/v9_declared_quarters.dart';
import 'migrations/v10_expenses.dart';
import 'migrations/v11_assets.dart';
import 'migrations/v12_cloud_ids.dart';
import 'migrations/v13_assets_iva.dart';
import 'migrations/v14_app_events.dart';
import 'migrations/v15_invoice_email_logs.dart';
import 'migrations/v16_invoice_number_by_year.dart';
import 'migrations/v17_invoice_number_unique_by_year.dart';
import 'migrations/v18_sync_queue_soft_delete.dart';
import 'migrations/v19_client_whatsapp_phone.dart';
import 'migrations/v20_invoice_number_changes.dart';
import 'migrations/v21_gig_status_refactor.dart';
import 'migrations/v22_google_drive_integration.dart';
import 'migrations/v23_cloud_sync_checkpoint.dart';
import 'migrations/v24_attachment_health.dart';
import 'migrations/v25_drive_account_name.dart';
import 'migrations/v26_settings_sync_signature.dart';
import 'migrations/v27_attachment_file_metadata.dart';
import 'migrations/v28_drive_sync_queue_metadata.dart';
import 'migrations/v29_drive_sync_queue_remote_fields.dart';
import 'migrations/v30_settings_sync_security_theme.dart';
import 'migrations/v31_expenses_assets_soft_delete.dart';
import 'migrations/v32_settings_irpf_default.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;
  String? _activeUserId;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  String? get activeUserId => _activeUserId;

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbName = _dbNameForUser(_activeUserId);
    final path = join(dbPath, dbName);

    return await openDatabase(
      path,
      version: 32,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  String _dbNameForUser(String? userId) {
    final clean = (userId ?? '').trim();
    if (clean.isEmpty) return 'misbolos_guest.db';
    final safe = clean.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'misbolos_$safe.db';
  }

  Future<void> switchToUserDatabase(String? userId) async {
    final nextUserId = (userId ?? '').trim().isEmpty ? null : userId!.trim();
    if (_database != null && _activeUserId == nextUserId) {
      return;
    }
    await close();
    _activeUserId = nextUserId;
    _database = await _initDatabase();
  }

  Future<void> _onCreate(Database db, int version) async {
    final statements = v1InitialMigration.split(';');
    for (final statement in statements) {
      final trimmed = statement.trim();
      if (trimmed.isNotEmpty) {
        await db.execute(trimmed);
      }
    }
    // Apply all migrations for fresh installs
    if (version >= 2) {
      await _applyMigration(db, v2AddProvinciaCp);
    }
    if (version >= 3) {
      await _applyMigration(db, v3AddClientProvinciaAlias);
    }
    if (version >= 4) {
      await _applyMigration(db, v4AddIrpf);
    }
    if (version >= 5) {
      await _applyMigration(db, v5AddLogoSize);
    }
    if (version >= 6) {
      await _applyMigration(db, v6AddPdfTheme);
    }
    if (version >= 7) {
      await _applyMigration(db, v7PendingDeletions);
    }
    if (version >= 8) {
      await _applyMigration(db, v8AddClientAliases);
    }
    if (version >= 9) {
      await _applyMigration(db, v9DeclaredQuarters);
    }
    if (version >= 10) {
      await _applyMigration(db, v10Expenses);
    }
    if (version >= 11) {
      await _applyMigration(db, v11Assets);
    }
    if (version >= 12) {
      await _applyMigration(db, v12CloudIds);
    }
    if (version >= 13) {
      await _applyMigration(db, v13AssetsIva);
    }
    if (version >= 14) {
      await _applyMigration(db, v14AppEvents);
    }
    if (version >= 15) {
      await _applyMigration(db, v15InvoiceEmailLogs);
    }
    if (version >= 16) {
      await _applyMigration(db, v16InvoiceNumberByYear);
    }
    if (version >= 17) {
      await _applyMigration(db, v17InvoiceNumberUniqueByYear);
    }
    if (version >= 18) {
      await _applyMigration(db, v18SyncQueueSoftDelete);
    }
    if (version >= 19) {
      await _applyMigration(db, v19ClientWhatsappPhone);
    }
    if (version >= 20) {
      await _applyMigration(db, v20InvoiceNumberChanges);
    }
    if (version >= 21) {
      await _applyMigration(db, v21GigStatusRefactor);
    }
    if (version >= 22) {
      await _applyMigration(db, v22GoogleDriveIntegration);
    }
    if (version >= 23) {
      await _applyMigration(db, v23CloudSyncCheckpoint);
    }
    if (version >= 24) {
      await _applyMigration(db, v24AttachmentHealth);
    }
    if (version >= 25) {
      await _applyMigration(db, v25DriveAccountName);
    }
    if (version >= 26) {
      await _applyMigration(db, v26SettingsSyncSignature);
    }
    if (version >= 27) {
      await _applyMigration(db, v27AttachmentFileMetadata);
    }
    if (version >= 28) {
      await _applyMigration(db, v28DriveSyncQueueMetadata);
    }
    if (version >= 29) {
      await _applyMigration(db, v29DriveSyncQueueRemoteFields);
    }
    if (version >= 30) {
      await _applyMigration(db, v30SettingsSyncSecurityTheme);
    }
    if (version >= 31) {
      await _applyMigration(db, v31ExpensesAssetsSoftDelete);
    }
    if (version >= 32) {
      await _applyMigration(db, v32SettingsIrpfDefault);
    }
    await _ensureSoftDeleteColumns(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _applyMigration(db, v2AddProvinciaCp);
    }
    if (oldVersion < 3) {
      await _applyMigration(db, v3AddClientProvinciaAlias);
    }
    if (oldVersion < 4) {
      await _applyMigration(db, v4AddIrpf);
    }
    if (oldVersion < 5) {
      await _applyMigration(db, v5AddLogoSize);
    }
    if (oldVersion < 6) {
      await _applyMigration(db, v6AddPdfTheme);
    }
    if (oldVersion < 7) {
      await _applyMigration(db, v7PendingDeletions);
    }
    if (oldVersion < 8) {
      await _applyMigration(db, v8AddClientAliases);
    }
    if (oldVersion < 9) {
      await _applyMigration(db, v9DeclaredQuarters);
    }
    if (oldVersion < 10) {
      await _applyMigration(db, v10Expenses);
    }
    if (oldVersion < 11) {
      await _applyMigration(db, v11Assets);
    }
    if (oldVersion < 12) {
      await _applyMigration(db, v12CloudIds);
    }
    if (oldVersion < 13) {
      await _applyMigration(db, v13AssetsIva);
    }
    if (oldVersion < 14) {
      await _applyMigration(db, v14AppEvents);
    }
    if (oldVersion < 15) {
      await _applyMigration(db, v15InvoiceEmailLogs);
    }
    if (oldVersion < 16) {
      await _applyMigration(db, v16InvoiceNumberByYear);
    }
    if (oldVersion < 17) {
      await _applyMigration(db, v17InvoiceNumberUniqueByYear);
    }
    if (oldVersion < 18) {
      await _applyMigration(db, v18SyncQueueSoftDelete);
    }
    if (oldVersion < 19) {
      await _applyMigration(db, v19ClientWhatsappPhone);
    }
    if (oldVersion < 20) {
      await _applyMigration(db, v20InvoiceNumberChanges);
    }
    if (oldVersion < 21) {
      await _applyMigration(db, v21GigStatusRefactor);
    }
    if (oldVersion < 22) {
      await _applyMigration(db, v22GoogleDriveIntegration);
    }
    if (oldVersion < 23) {
      await _applyMigration(db, v23CloudSyncCheckpoint);
    }
    if (oldVersion < 24) {
      await _applyMigration(db, v24AttachmentHealth);
    }
    if (oldVersion < 25) {
      await _applyMigration(db, v25DriveAccountName);
    }
    if (oldVersion < 26) {
      await _applyMigration(db, v26SettingsSyncSignature);
    }
    if (oldVersion < 27) {
      await _applyMigration(db, v27AttachmentFileMetadata);
    }
    if (oldVersion < 28) {
      await _applyMigration(db, v28DriveSyncQueueMetadata);
    }
    if (oldVersion < 29) {
      await _applyMigration(db, v29DriveSyncQueueRemoteFields);
    }
    if (oldVersion < 30) {
      await _applyMigration(db, v30SettingsSyncSecurityTheme);
    }
    if (oldVersion < 31) {
      await _applyMigration(db, v31ExpensesAssetsSoftDelete);
    }
    if (oldVersion < 32) {
      await _applyMigration(db, v32SettingsIrpfDefault);
    }
    await _ensureSoftDeleteColumns(db);
  }

  Future<void> _applyMigration(Database db, String migration) async {
    final statements = migration.split(';');
    for (final statement in statements) {
      final trimmed = statement.trim();
      if (trimmed.isNotEmpty) {
        try {
          await db.execute(trimmed);
        } catch (e) {
          // Ignorar errores de columna duplicada (ya existe)
          if (!e.toString().contains('duplicate column')) {
            rethrow;
          }
        }
      }
    }
  }

  Future<void> _ensureSoftDeleteColumns(Database db) async {
    await _ensureColumnExists(db, table: 'expenses', column: 'deleted_at');
    await _ensureColumnExists(db, table: 'assets', column: 'deleted_at');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_deleted_at ON expenses(deleted_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_assets_deleted_at ON assets(deleted_at)',
    );
  }

  Future<void> _ensureColumnExists(
    Database db, {
    required String table,
    required String column,
  }) async {
    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (tableRows.isEmpty) return;

    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (exists) return;

    await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  // ================== PENDING DELETIONS ==================

  Future<void> addPendingDeletion(String tableName, String recordId) async {
    final db = await database;
    await db.insert('pending_deletions', {
      'id': '${tableName}_${recordId}_${DateTime.now().millisecondsSinceEpoch}',
      'table_name': tableName,
      'record_id': recordId,
      'deleted_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPendingDeletions() async {
    final db = await database;
    return db.query('pending_deletions');
  }

  Future<void> removePendingDeletion(String id) async {
    final db = await database;
    await db.delete('pending_deletions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearUserScopedData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('invoice_email_logs');
      await txn.delete('invoice_number_changes');
      await txn.delete('sync_queue');
      await txn.delete('pending_deletions');
      await txn.delete('drive_sync_queue');
      await txn.delete('expenses');
      await txn.delete('assets');
      await txn.delete('invoices');
      await txn.delete('gigs');
      await txn.delete('clients');
    });
  }
}
