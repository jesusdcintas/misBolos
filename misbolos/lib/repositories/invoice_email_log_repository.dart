import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/invoice_email_log.dart';

class InvoiceEmailLogRepository {
  static final InvoiceEmailLogRepository instance =
      InvoiceEmailLogRepository._();
  InvoiceEmailLogRepository._();

  Future<void> insert(InvoiceEmailLog log) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'invoice_email_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(InvoiceEmailLog log) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'invoice_email_logs',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<List<InvoiceEmailLog>> getByInvoice(String invoiceId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoice_email_logs',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'created_at DESC',
    );
    return maps.map(InvoiceEmailLog.fromMap).toList();
  }

  Future<List<InvoiceEmailLog>> getRecent({int limit = 100}) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoice_email_logs',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(InvoiceEmailLog.fromMap).toList();
  }
}
