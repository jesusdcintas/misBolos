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

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'misbolos.db');

    return await openDatabase(
      path,
      version: 19,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
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
}
