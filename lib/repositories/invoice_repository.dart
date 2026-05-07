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

  Future<List<Invoice>> getAll({bool includeDeleted = false}) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'fecha DESC, numero DESC',
    );
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
      where: 'gig_id = ? AND deleted_at IS NULL',
      whereArgs: [gigId],
    );
    if (maps.isEmpty) return null;
    return Invoice.fromMap(maps.first);
  }

  Future<List<Invoice>> getByStatus(InvoiceStatus status) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: 'status = ? AND deleted_at IS NULL',
      whereArgs: [status.dbValue],
      orderBy: 'numero ASC',
    );
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getByClientId(String clientId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: 'client_id = ? AND deleted_at IS NULL',
      whereArgs: [clientId],
      orderBy: 'numero ASC',
    );
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getByFiscalYear(int year) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where:
          "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND deleted_at IS NULL",
      whereArgs: [year],
      orderBy: 'numero ASC, fecha ASC, created_at ASC, id ASC',
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
        AND deleted_at IS NULL
      ''',
      [year],
    );
    final maxNum = result.first['max_num'] as int?;
    return (maxNum ?? 0) + 1;
  }

  Future<void> insert(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('invoices', invoice.touch().toMap());
  }

  Future<void> insertAndLinkGig(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.insert(
        'invoices',
        invoice.copyWith(updatedAt: DateTime.now()).toMap(),
      );
      await txn.update(
        'gigs',
        {
          'invoice_id': invoice.id,
          'status': GigStatus.facturaGenerada.dbValue,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [invoice.gigId],
      );
    });
  }

  Future<void> update(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'invoices',
      invoice.touch().toMap(),
      where: 'id = ?',
      whereArgs: [invoice.id],
    );
  }

  Future<void> updateStatus(String id, InvoiceStatus status) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'invoices',
      {
        'status': status.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'invoices',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
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
        {
          'invoice_id': null,
          'status': GigStatus.pendiente.dbValue,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND invoice_id = ?',
        whereArgs: [invoice.gigId, invoice.id],
      );
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'invoices',
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return invoice;
    });
  }

  /// Actualiza el número de una factura específica
  Future<void> updateNumber(String id, int newNumber) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'invoices',
      {'numero': newNumber, 'updated_at': DateTime.now().toIso8601String()},
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
          ? "numero = ? AND CAST(strftime('%Y', fecha) AS INTEGER) = ? AND id != ? AND deleted_at IS NULL"
          : "numero = ? AND CAST(strftime('%Y', fecha) AS INTEGER) = ? AND deleted_at IS NULL",
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
        where:
            "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND deleted_at IS NULL",
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
        ? "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND deleted_at IS NULL"
        : "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND status != ? AND deleted_at IS NULL";
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
          ? "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND deleted_at IS NULL"
          : "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND status != ? AND deleted_at IS NULL";
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

  Future<ManualRenumberResult> renumberInvoicesManually({
    required int fiscalYear,
    required Map<String, int> newNumbersByInvoiceId,
  }) async {
    if (newNumbersByInvoiceId.isEmpty) {
      throw StateError('No hay facturas para reenumerar.');
    }

    final targetIds = newNumbersByInvoiceId.keys.toList(growable: false);
    final targetNumbers = newNumbersByInvoiceId.values.toList(growable: false);
    for (final number in targetNumbers) {
      if (number <= 0) {
        throw StateError('Todos los nuevos números deben ser enteros positivos.');
      }
    }
    if (targetNumbers.toSet().length != targetNumbers.length) {
      throw StateError('Hay números duplicados en la nueva numeración.');
    }

    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) async {
      final placeholdersIds = List.filled(targetIds.length, '?').join(',');
      final rows = await txn.rawQuery(
        '''
        SELECT *
        FROM invoices
        WHERE id IN ($placeholdersIds)
          AND deleted_at IS NULL
        ''',
        targetIds,
      );

      if (rows.length != targetIds.length) {
        throw StateError('Alguna factura del lote no existe o está eliminada.');
      }

      for (final row in rows) {
        final invoiceYear = _yearFromIso(row['fecha'] as String);
        if (invoiceYear != fiscalYear) {
          throw StateError(
            'Todas las facturas deben pertenecer al año fiscal $fiscalYear.',
          );
        }
      }

      final placeholdersNumbers = List.filled(targetNumbers.length, '?').join(
        ',',
      );
      final outsideCollision = await txn.rawQuery(
        '''
        SELECT id, numero
        FROM invoices
        WHERE CAST(strftime('%Y', fecha) AS INTEGER) = ?
          AND deleted_at IS NULL
          AND numero IN ($placeholdersNumbers)
          AND id NOT IN ($placeholdersIds)
        LIMIT 1
        ''',
        <Object?>[fiscalYear, ...targetNumbers, ...targetIds],
      );
      if (outsideCollision.isNotEmpty) {
        final numero = outsideCollision.first['numero'];
        throw StateError(
          'El número $numero choca con una factura fuera del lote.',
        );
      }

      final oldById = <String, int>{};
      for (final row in rows) {
        oldById[row['id'] as String] = row['numero'] as int;
      }

      final now = DateTime.now().toIso8601String();
      for (var i = 0; i < targetIds.length; i++) {
        await txn.update(
          'invoices',
          {'numero': -9000000 - i, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [targetIds[i]],
        );
      }

      for (final id in targetIds) {
        final newNumber = newNumbersByInvoiceId[id]!;
        await txn.update(
          'invoices',
          {'numero': newNumber, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      final updatedRows = await txn.rawQuery(
        '''
        SELECT *
        FROM invoices
        WHERE id IN ($placeholdersIds)
        ''',
        targetIds,
      );
      final updatedInvoices = updatedRows
          .map((row) => Invoice.fromMap(row))
          .toList(growable: false);

      final changes = <ManualRenumberChange>[];
      for (final updated in updatedInvoices) {
        final oldNumber = oldById[updated.id];
        if (oldNumber == null) continue;
        changes.add(
          ManualRenumberChange(
            invoiceId: updated.id,
            oldNumber: oldNumber,
            newNumber: updated.numero,
          ),
        );
      }

      return ManualRenumberResult(
        fiscalYear: fiscalYear,
        updatedInvoices: updatedInvoices,
        changes: changes,
      );
    });
  }

  int _yearFromIso(String isoDate) => DateTime.parse(isoDate).year;
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

class ManualRenumberChange {
  final String invoiceId;
  final int oldNumber;
  final int newNumber;

  ManualRenumberChange({
    required this.invoiceId,
    required this.oldNumber,
    required this.newNumber,
  });
}

class ManualRenumberResult {
  final int fiscalYear;
  final List<Invoice> updatedInvoices;
  final List<ManualRenumberChange> changes;

  ManualRenumberResult({
    required this.fiscalYear,
    required this.updatedInvoices,
    required this.changes,
  });
}
