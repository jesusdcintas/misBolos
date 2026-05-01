import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/gig.dart';
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
    final maps = await db.query('invoices', orderBy: 'fecha DESC, numero DESC');
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
    final maps = await db.query(
      'invoices',
      where: 'gig_id = ?',
      whereArgs: [gigId],
    );
    if (maps.isEmpty) return null;
    return Invoice.fromMap(maps.first);
  }

  Future<List<Invoice>> getByStatus(InvoiceStatus status) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: 'status = ?',
      whereArgs: [status.dbValue],
      orderBy: 'numero ASC',
    );
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getByClientId(String clientId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'numero ASC',
    );
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<int> getNextNumber() async {
    return getNextNumberForYear(DateTime.now().year);
  }

  Future<int> getNextNumberForYear(int year) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery(
      '''
      SELECT MAX(numero) as max_num
      FROM invoices
      WHERE CAST(strftime('%Y', fecha) AS INTEGER) = ?
      ''',
      [year],
    );
    final maxNum = result.first['max_num'] as int?;
    return (maxNum ?? 0) + 1;
  }

  Future<void> insert(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('invoices', invoice.toMap());
  }

  Future<void> insertAndLinkGig(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.insert('invoices', invoice.toMap());
      await txn.update(
        'gigs',
        {'invoice_id': invoice.id, 'status': GigStatus.facturaGenerada.dbValue},
        where: 'id = ?',
        whereArgs: [invoice.gigId],
      );
    });
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

  Future<Invoice?> deleteAndUnlinkGig(String id) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'invoices',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return null;
      final invoice = Invoice.fromMap(rows.first);
      await txn.update(
        'gigs',
        {'invoice_id': null, 'status': GigStatus.pendiente.dbValue},
        where: 'id = ? AND invoice_id = ?',
        whereArgs: [invoice.gigId, invoice.id],
      );
      await txn.delete('invoices', where: 'id = ?', whereArgs: [id]);
      return invoice;
    });
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
  Future<bool> isNumberTaken(
    int number, {
    required int year,
    String? excludeId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'invoices',
      where: excludeId != null
          ? "numero = ? AND CAST(strftime('%Y', fecha) AS INTEGER) = ? AND id != ?"
          : "numero = ? AND CAST(strftime('%Y', fecha) AS INTEGER) = ?",
      whereArgs: excludeId != null ? [number, year, excludeId] : [number, year],
    );
    return result.isNotEmpty;
  }

  /// Reenumera facturas por año, ordenadas por fecha.
  ///
  /// Usa dos fases para evitar choques temporales con el índice único
  /// `(año, numero)` mientras se reasignan números que ya existen en ese año.
  Future<List<Invoice>> renumberYear(int year, {int startFrom = 1}) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'invoices',
        where: "CAST(strftime('%Y', fecha) AS INTEGER) = ?",
        whereArgs: [year],
        orderBy: 'fecha ASC, created_at ASC, id ASC',
      );

      for (var i = 0; i < rows.length; i++) {
        await txn.update(
          'invoices',
          {'numero': -1000000 - i},
          where: 'id = ?',
          whereArgs: [rows[i]['id']],
        );
      }

      var currentNumber = startFrom;
      final renumbered = <Invoice>[];
      for (final row in rows) {
        await txn.update(
          'invoices',
          {'numero': currentNumber},
          where: 'id = ?',
          whereArgs: [row['id']],
        );

        final updatedRows = await txn.query(
          'invoices',
          where: 'id = ?',
          whereArgs: [row['id']],
          limit: 1,
        );
        renumbered.add(Invoice.fromMap(updatedRows.first));
        currentNumber++;
      }

      return renumbered;
    });
  }

  Future<List<InvoiceGapPreviewItem>> previewCloseGapsYear(
    int year, {
    bool includeDrafts = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final where = includeDrafts
        ? "CAST(strftime('%Y', fecha) AS INTEGER) = ?"
        : "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND status != ?";
    final args = includeDrafts
        ? [year]
        : [year, InvoiceStatus.borrador.dbValue];

    final rows = await db.query(
      'invoices',
      where: where,
      whereArgs: args,
      orderBy: 'fecha ASC, numero ASC, id ASC',
    );

    final preview = <InvoiceGapPreviewItem>[];
    var next = 1;
    for (final row in rows) {
      final current = row['numero'] as int;
      if (current != next) {
        preview.add(
          InvoiceGapPreviewItem(
            id: row['id'] as String,
            fromNumber: current,
            toNumber: next,
            fecha: DateTime.parse(row['fecha'] as String),
          ),
        );
      }
      next++;
    }
    return preview;
  }

  Future<List<Invoice>> closeGapsYear(
    int year, {
    bool includeDrafts = false,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) async {
      final where = includeDrafts
          ? "CAST(strftime('%Y', fecha) AS INTEGER) = ?"
          : "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND status != ?";
      final args = includeDrafts
          ? <Object?>[year]
          : <Object?>[year, InvoiceStatus.borrador.dbValue];

      final rows = await txn.query(
        'invoices',
        where: where,
        whereArgs: args,
        orderBy: 'fecha ASC, numero ASC, id ASC',
      );

      for (var i = 0; i < rows.length; i++) {
        await txn.update(
          'invoices',
          {'numero': -1000000 - i},
          where: 'id = ?',
          whereArgs: [rows[i]['id']],
        );
      }

      final updated = <Invoice>[];
      var next = 1;
      for (final row in rows) {
        await txn.update(
          'invoices',
          {'numero': next},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        final refreshed = await txn.query(
          'invoices',
          where: 'id = ?',
          whereArgs: [row['id']],
          limit: 1,
        );
        updated.add(Invoice.fromMap(refreshed.first));
        next++;
      }
      return updated;
    });
  }
}

class InvoiceGapPreviewItem {
  final String id;
  final int fromNumber;
  final int toNumber;
  final DateTime fecha;

  InvoiceGapPreviewItem({
    required this.id,
    required this.fromNumber,
    required this.toNumber,
    required this.fecha,
  });
}
