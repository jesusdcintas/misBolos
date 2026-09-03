import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/gig.dart';
import '../models/invoice.dart';

class GigBatchDeleteResult {
  final Set<String> deletedGigIds;
  final Set<String> deletedInvoiceIds;

  const GigBatchDeleteResult({
    required this.deletedGigIds,
    required this.deletedInvoiceIds,
  });
}

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

  Future<List<Gig>> getAll({bool includeDeleted = false}) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'gigs',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'fecha ASC',
    );
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
      where: 'client_id = ? AND deleted_at IS NULL',
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
      where: 'fecha >= ? AND fecha <= ? AND deleted_at IS NULL',
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
      where: 'fecha >= ? AND status != ? AND deleted_at IS NULL',
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
      where: 'deleted_at IS NULL',
      orderBy: 'fecha DESC',
      limit: limit,
    );
    return maps.map((m) => Gig.fromMap(m)).toList();
  }

  Future<List<Gig>> getFacturablesEnviadas() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'gigs',
      where: 'facturable = 1 AND status = ? AND deleted_at IS NULL',
      whereArgs: [GigStatus.facturado.dbValue],
    );
    return maps.map((m) => Gig.fromMap(m)).toList();
  }

  Future<void> insert(Gig gig) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('gigs', gig.touch().toMap());
    await _ensureInvoiceConsistency(db, gig);
  }

  Future<void> update(Gig gig) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'gigs',
      gig.touch().toMap(),
      where: 'id = ?',
      whereArgs: [gig.id],
    );
    await _ensureInvoiceConsistency(db, gig);
  }

  Future<void> updateStatus(String id, GigStatus status) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'gigs',
      {
        'status': status.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    // Si alguien marca un bolo como "facturado/cobrado" sin que
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
        InvoiceStatus.borrador => GigStatus.facturado,
        InvoiceStatus.enviada => GigStatus.facturado,
        InvoiceStatus.pagada => GigStatus.cobrado,
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
      {'invoice_id': invoiceId, 'status': GigStatus.facturado.dbValue},
      where: 'id = ?',
      whereArgs: [gigId],
    );
    final gig = await getById(gigId);
    if (gig != null) {
      await _ensureInvoiceConsistency(db, gig.copyWith(invoiceId: invoiceId));
    }
  }

  Future<void> delete(String id) async {
    await deleteBatch({id});
  }

  Future<void> updateStatusBatch(Set<String> ids, GigStatus status) async {
    if (ids.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'gigs',
      {
        'status': status.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
  }

  Future<void> updateFacturableBatch(Set<String> ids, bool facturable) async {
    if (ids.isEmpty) return;
    final db = await DatabaseHelper.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'gigs',
      {
        'facturable': facturable ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id IN ($placeholders)',
      whereArgs: ids.toList(),
    );
  }

  Future<GigBatchDeleteResult> deleteBatch(Set<String> ids) async {
    if (ids.isEmpty) {
      return const GigBatchDeleteResult(
        deletedGigIds: <String>{},
        deletedInvoiceIds: <String>{},
      );
    }
    final db = await DatabaseHelper.instance.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final gigIds = ids.toList();

    return db.transaction((txn) async {
      final invoicesRows = await txn.query(
        'invoices',
        columns: ['id'],
        where: 'gig_id IN ($placeholders)',
        whereArgs: gigIds,
      );
      final invoiceIds = invoicesRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toSet();

      if (invoiceIds.isNotEmpty) {
        final invPlaceholders = List.filled(invoiceIds.length, '?').join(',');
        final invArgs = invoiceIds.toList();

        // Romper referencia circular antes de borrar facturas.
        await txn.update(
          'gigs',
          {'invoice_id': null},
          where: 'id IN ($placeholders)',
          whereArgs: gigIds,
        );

        // Hijos directos conocidos por invoice_id.
        await _deleteIfTableExists(
          txn,
          'invoice_email_logs',
          'invoice_id IN ($invPlaceholders)',
          invArgs,
        );
        await _deleteIfTableExists(
          txn,
          'invoice_items',
          'invoice_id IN ($invPlaceholders)',
          invArgs,
        );
        await _deleteIfTableExists(
          txn,
          'payments',
          'invoice_id IN ($invPlaceholders)',
          invArgs,
        );
      }

      // Cualquier FK adicional hacia invoices/gigs.
      await _deleteDynamicChildrenByFk(
        txn,
        parentTable: 'invoices',
        ids: invoiceIds,
      );
      await _deleteDynamicChildrenByFk(txn, parentTable: 'gigs', ids: ids);

      if (invoiceIds.isNotEmpty) {
        final invPlaceholders = List.filled(invoiceIds.length, '?').join(',');
        final deletedAt = DateTime.now().toIso8601String();
        await txn.update(
          'invoices',
          {'deleted_at': deletedAt, 'updated_at': deletedAt},
          where: 'id IN ($invPlaceholders)',
          whereArgs: invoiceIds.toList(),
        );
      }

      final deletedAt = DateTime.now().toIso8601String();
      await txn.update(
        'gigs',
        {'deleted_at': deletedAt, 'updated_at': deletedAt},
        where: 'id IN ($placeholders)',
        whereArgs: gigIds,
      );

      return GigBatchDeleteResult(
        deletedGigIds: ids,
        deletedInvoiceIds: invoiceIds,
      );
    });
  }

  Future<void> _deleteIfTableExists(
    Transaction txn,
    String tableName,
    String where,
    List<Object?> whereArgs,
  ) async {
    final exists = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tableName],
    );
    if (exists.isEmpty) return;
    await txn.delete(tableName, where: where, whereArgs: whereArgs);
  }

  Future<void> _deleteDynamicChildrenByFk(
    Transaction txn, {
    required String parentTable,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final args = ids.toList();
    final tables = await txn.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    for (final row in tables) {
      final table = row['name']?.toString();
      if (table == null || table.isEmpty) continue;
      if (table == parentTable) continue;
      if (table == 'gigs' && parentTable == 'invoices') continue;

      final fkRows = await txn.rawQuery("PRAGMA foreign_key_list('$table')");
      for (final fk in fkRows) {
        final refTable = fk['table']?.toString();
        final fromColumn = fk['from']?.toString();
        if (refTable != parentTable ||
            fromColumn == null ||
            fromColumn.isEmpty) {
          continue;
        }
        await txn.delete(
          table,
          where: '$fromColumn IN ($placeholders)',
          whereArgs: args,
        );
      }
    }
  }

  Future<void> _ensureInvoiceConsistency(Database db, Gig gig) async {
    if (!gig.facturable) return;
    if (gig.status == GigStatus.confirmado ||
        gig.status == GigStatus.cancelado ||
        gig.status == GigStatus.cobradoB) {
      return;
    }

    final desiredInvoiceStatus = switch (gig.status) {
      GigStatus.facturado => InvoiceStatus.enviada,
      GigStatus.cobrado => InvoiceStatus.pagada,
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
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [invoiceId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    // Evitar duplicar por gig_id si ya hay una factura asociada.
    final byGig = await db.query(
      'invoices',
      columns: ['id'],
      where: 'gig_id = ? AND deleted_at IS NULL',
      whereArgs: [gig.id],
      limit: 1,
    );
    if (byGig.isNotEmpty) {
      final existingId = byGig.first['id']?.toString();
      if (existingId != null &&
          existingId.isNotEmpty &&
          existingId != invoiceId) {
        await db.update(
          'gigs',
          {'invoice_id': existingId},
          where: 'id = ?',
          whereArgs: [gig.id],
        );
      }
      return;
    }

    final nextNumResult = await db.rawQuery(
      '''
      SELECT MAX(numero) as max_num
      FROM invoices
      WHERE CAST(strftime('%Y', fecha) AS INTEGER) = ?
        AND deleted_at IS NULL
        AND invoice_type = ?
      ''',
      [gig.fecha.year, InvoiceType.normal.dbValue],
    );
    final maxNum = nextNumResult.first['max_num'] as int?;
    final nextNum = (maxNum ?? 0) + 1;

    final description = (gig.notas?.trim().isNotEmpty ?? false)
        ? gig.notas!.trim().toUpperCase()
        : 'DJ SET';
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
