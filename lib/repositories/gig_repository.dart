import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/gig.dart';

class GigRepository {
  static final GigRepository instance = GigRepository._();
  GigRepository._();

  Future<void> upsert(Gig gig) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'gigs',
      gig.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Gig>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('gigs', orderBy: 'fecha ASC');
    return maps.map((m) => Gig.fromMap(m)).toList();
  }

  Future<Gig?> getById(String id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('gigs', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Gig.fromMap(maps.first);
  }

  Future<List<Gig>> getByClientId(String clientId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'gigs',
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'fecha ASC',
    );
    return maps.map((m) => Gig.fromMap(m)).toList();
  }

  Future<List<Gig>> getByMonth(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'gigs',
      where: 'fecha >= ? AND fecha <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'fecha ASC',
    );
    return maps.map((m) => Gig.fromMap(m)).toList();
  }

  Future<List<Gig>> getUpcoming() async {
    final now = DateTime.now().toIso8601String();
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'gigs',
      where: 'fecha >= ? AND status != ?',
      whereArgs: [now, 'cancelado'],
      orderBy: 'fecha ASC',
      limit: 10,
    );
    return maps.map((m) => Gig.fromMap(m)).toList();
  }

  Future<List<Gig>> getRecent({int limit = 5}) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'gigs',
      orderBy: 'fecha DESC',
      limit: limit,
    );
    return maps.map((m) => Gig.fromMap(m)).toList();
  }

  Future<List<Gig>> getFacturablesEnviadas() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'gigs',
      where: 'facturable = 1 AND status = ?',
      whereArgs: ['factura_enviada'],
    );
    return maps.map((m) => Gig.fromMap(m)).toList();
  }

  Future<void> insert(Gig gig) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('gigs', gig.toMap());
  }

  Future<void> update(Gig gig) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'gigs',
      gig.toMap(),
      where: 'id = ?',
      whereArgs: [gig.id],
    );
  }

  Future<void> updateStatus(String id, GigStatus status) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'gigs',
      {'status': status.dbValue},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> linkInvoice(String gigId, String invoiceId) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'gigs',
      {
        'invoice_id': invoiceId,
        'status': GigStatus.facturaGenerada.dbValue,
      },
      where: 'id = ?',
      whereArgs: [gigId],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('gigs', where: 'id = ?', whereArgs: [id]);
  }
}
