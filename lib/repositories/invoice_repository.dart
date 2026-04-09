import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/invoice.dart';

class InvoiceRepository {
  static final InvoiceRepository instance = InvoiceRepository._();
  InvoiceRepository._();

  Future<void> upsert(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'invoices',
      invoice.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Invoice>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('invoices', orderBy: 'numero DESC');
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<Invoice?> getById(String id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Invoice.fromMap(maps.first);
  }

  Future<Invoice?> getByGigId(String gigId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('invoices', where: 'gig_id = ?', whereArgs: [gigId]);
    if (maps.isEmpty) return null;
    return Invoice.fromMap(maps.first);
  }

  Future<List<Invoice>> getByStatus(InvoiceStatus status) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: 'status = ?',
      whereArgs: [status.dbValue],
      orderBy: 'numero DESC',
    );
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getByClientId(String clientId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'numero DESC',
    );
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<int> getNextNumber() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('SELECT MAX(numero) as max_num FROM invoices');
    final maxNum = result.first['max_num'] as int?;
    return (maxNum ?? 0) + 1;
  }

  Future<void> insert(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('invoices', invoice.toMap());
  }

  Future<void> update(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'invoices',
      invoice.toMap(),
      where: 'id = ?',
      whereArgs: [invoice.id],
    );
  }

  Future<void> updateStatus(String id, InvoiceStatus status) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'invoices',
      {'status': status.dbValue},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  /// Actualiza el número de una factura específica
  Future<void> updateNumber(String id, int newNumber) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'invoices',
      {'numero': newNumber},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Verifica si un número de factura ya existe (excluyendo una factura específica)
  Future<bool> isNumberTaken(int number, {String? excludeId}) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'invoices',
      where: excludeId != null ? 'numero = ? AND id != ?' : 'numero = ?',
      whereArgs: excludeId != null ? [number, excludeId] : [number],
    );
    return result.isNotEmpty;
  }

  /// Reenumera todas las facturas ordenadas por fecha, empezando desde un número dado
  Future<void> renumberAll(int startFrom) async {
    final db = await DatabaseHelper.instance.database;
    final invoices = await db.query('invoices', orderBy: 'fecha ASC, created_at ASC');
    
    int currentNumber = startFrom;
    for (final inv in invoices) {
      await db.update(
        'invoices',
        {'numero': currentNumber},
        where: 'id = ?',
        whereArgs: [inv['id']],
      );
      currentNumber++;
    }
  }
}
