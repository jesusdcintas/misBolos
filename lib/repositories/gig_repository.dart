import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/gig.dart';
import '../models/invoice.dart';

class GigRepository {
  static final GigRepository instance = GigRepository._();
  GigRepository._();

  static const _uuid = Uuid();

  Future<void> upsert(Gig gig) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'gigs',
      gig.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _ensureInvoiceConsistency(db, gig);
  }

  Future<List<Gig>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('gigs', orderBy: 'fecha ASC');
    final gigs = maps.map((m) => Gig.fromMap(m)).toList();
    // Reparar inconsistencias antiguas (bolo con estado de factura sin invoice).
    for (final g in gigs) {
      await _ensureInvoiceConsistency(db, g);
    }
    return gigs;
  }

  Future<Gig?> getById(String id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('gigs', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final gig = Gig.fromMap(maps.first);
    await _ensureInvoiceConsistency(db, gig);
    return gig;
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
    final maps = await db.query('gigs', orderBy: 'fecha DESC', limit: limit);
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
    await _ensureInvoiceConsistency(db, gig);
  }

  Future<void> update(Gig gig) async {
    final db = await DatabaseHelper.instance.database;
    await db.update('gigs', gig.toMap(), where: 'id = ?', whereArgs: [gig.id]);
    await _ensureInvoiceConsistency(db, gig);
  }

  Future<void> updateStatus(String id, GigStatus status) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'gigs',
      {'status': status.dbValue},
      where: 'id = ?',
      whereArgs: [id],
    );
    // Si alguien marca un bolo como "factura generada/enviada/pagado" sin que
    // exista la factura, crear una mínima para mantener consistencia.
    final gig = await getById(id);
    if (gig != null) {
      await _ensureInvoiceConsistency(db, gig.copyWith(status: status));
    }
  }

  Future<int> repairStatusesFromInvoices(List<Invoice> invoices) async {
    final db = await DatabaseHelper.instance.database;
    var repaired = 0;

    for (final invoice in invoices) {
      final expectedStatus = switch (invoice.status) {
        InvoiceStatus.borrador => GigStatus.facturaGenerada,
        InvoiceStatus.enviada => GigStatus.facturaEnviada,
        InvoiceStatus.pagada => GigStatus.pagado,
      };

      final count = await db.update(
        'gigs',
        {'status': expectedStatus.dbValue, 'invoice_id': invoice.id},
        where: '''
          id = ?
          AND facturable = 1
          AND status != ?
          AND status != ?
        ''',
        whereArgs: [
          invoice.gigId,
          expectedStatus.dbValue,
          GigStatus.cancelado.dbValue,
        ],
      );
      repaired += count;
    }

    return repaired;
  }

  Future<void> linkInvoice(String gigId, String invoiceId) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'gigs',
      {'invoice_id': invoiceId, 'status': GigStatus.facturaGenerada.dbValue},
      where: 'id = ?',
      whereArgs: [gigId],
    );
    final gig = await getById(gigId);
    if (gig != null) {
      await _ensureInvoiceConsistency(db, gig.copyWith(invoiceId: invoiceId));
    }
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('gigs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _ensureInvoiceConsistency(Database db, Gig gig) async {
    if (!gig.facturable) return;
    if (gig.status == GigStatus.pendiente ||
        gig.status == GigStatus.cancelado ||
        gig.status == GigStatus.cobradoEnB) {
      return;
    }

    final desiredInvoiceStatus = switch (gig.status) {
      GigStatus.facturaGenerada => InvoiceStatus.borrador,
      GigStatus.facturaEnviada => InvoiceStatus.enviada,
      GigStatus.pagado => InvoiceStatus.pagada,
      _ => InvoiceStatus.borrador,
    };

    // 1) Asegurar invoice_id
    var invoiceId = gig.invoiceId;
    if (invoiceId == null || invoiceId.trim().isEmpty) {
      invoiceId = _uuid.v4();
      await db.update(
        'gigs',
        {'invoice_id': invoiceId},
        where: 'id = ?',
        whereArgs: [gig.id],
      );
    }

    // 2) Si no existe factura con ese id, crearla.
    final existing = await db.query(
      'invoices',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    // Evitar duplicar por gig_id si ya hay una factura asociada.
    final byGig = await db.query(
      'invoices',
      columns: ['id'],
      where: 'gig_id = ?',
      whereArgs: [gig.id],
      limit: 1,
    );
    if (byGig.isNotEmpty) {
      final existingId = byGig.first['id']?.toString();
      if (existingId != null && existingId.isNotEmpty && existingId != invoiceId) {
        await db.update(
          'gigs',
          {'invoice_id': existingId},
          where: 'id = ?',
          whereArgs: [gig.id],
        );
      }
      return;
    }

    final nextNumResult =
        await db.rawQuery('SELECT MAX(numero) as max_num FROM invoices');
    final maxNum = nextNumResult.first['max_num'] as int?;
    final nextNum = (maxNum ?? 0) + 1;

    final description = (gig.notas?.trim().isNotEmpty ?? false)
        ? gig.notas!.trim().toUpperCase()
        : 'SONORIZACION';
    final subtotal = gig.cachet ?? 0.0;
    final items = [
      InvoiceLineItem(
        cantidad: 1,
        descripcion: description,
        precioUnitario: subtotal,
      ),
    ];

    final invoice = Invoice(
      id: invoiceId,
      numero: nextNum,
      fecha: gig.fecha,
      clientId: gig.clientId,
      gigId: gig.id,
      items: items,
      subtotal: subtotal,
      status: desiredInvoiceStatus,
    );

    await db.insert(
      'invoices',
      invoice.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
