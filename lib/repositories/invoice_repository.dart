import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/gig.dart';
import '../models/invoice.dart';

class InvoiceNumberChangeSource {
  static const createInvoice = 'create_invoice';
  static const manualRenumber = 'manual_renumber';

  static const allowed = {createInvoice, manualRenumber};
}

class InvoiceRepository {
  static final InvoiceRepository instance = InvoiceRepository._();
  InvoiceRepository._();

  Future<void> upsert(
    Invoice invoice, {
    String? allowedNumberChangeSource,
    String? reason,
    String? userId,
  }) async {
    if (invoice.numero <= 0) {
      throw StateError('No se puede guardar una factura con número temporal.');
    }
    final db = await DatabaseHelper.instance.database;
    final local = await getById(invoice.id);
    var invoiceToSave = invoice;

    if (local != null && local.numero != invoice.numero) {
      if (allowedNumberChangeSource ==
          InvoiceNumberChangeSource.manualRenumber) {
        await _recordInvoiceNumberChange(
          db,
          invoiceId: invoice.id,
          oldNumber: local.numero,
          newNumber: invoice.numero,
          source: allowedNumberChangeSource!,
          reason: reason,
          userId: userId,
        );
      } else {
        _logBlockedNumberChange(
          origin: allowedNumberChangeSource ?? 'generic_upsert',
          invoiceId: invoice.id,
          oldNumber: local.numero,
          attemptedNumber: invoice.numero,
        );
        invoiceToSave = invoice.copyWith(numero: local.numero);
      }
    }

    await db.insert(
      'invoices',
      invoiceToSave.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (local == null) {
      await _recordInvoiceNumberChange(
        db,
        invoiceId: invoiceToSave.id,
        oldNumber: null,
        newNumber: invoiceToSave.numero,
        source: InvoiceNumberChangeSource.createInvoice,
        reason: reason ?? 'upsert_new_invoice',
        userId: userId,
      );
    }
  }

  Future<List<Invoice>> getAll({bool includeDeleted = false}) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: includeDeleted ? null : 'deleted_at IS NULL AND numero > 0',
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
      where: 'gig_id = ? AND deleted_at IS NULL AND numero > 0',
      whereArgs: [gigId],
    );
    if (maps.isEmpty) return null;
    return Invoice.fromMap(maps.first);
  }

  Future<List<Invoice>> getByStatus(InvoiceStatus status) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: 'status = ? AND deleted_at IS NULL AND numero > 0',
      whereArgs: [status.dbValue],
      orderBy: 'numero ASC',
    );
    return maps.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getByClientId(String clientId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'invoices',
      where: 'client_id = ? AND deleted_at IS NULL AND numero > 0',
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
          "CAST(strftime('%Y', fecha) AS INTEGER) = ? AND deleted_at IS NULL AND numero > 0",
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
    if (invoice.numero <= 0) {
      throw StateError('No se puede crear una factura con número temporal.');
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      await txn.insert('invoices', invoice.touch().toMap());
      await _recordInvoiceNumberChange(
        txn,
        invoiceId: invoice.id,
        oldNumber: null,
        newNumber: invoice.numero,
        source: InvoiceNumberChangeSource.createInvoice,
      );
    });
  }

  Future<void> insertAndLinkGig(Invoice invoice) async {
    if (invoice.numero <= 0) {
      throw StateError('No se puede crear una factura con número temporal.');
    }
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.insert(
        'invoices',
        invoice.copyWith(updatedAt: DateTime.now()).toMap(),
      );
      await _recordInvoiceNumberChange(
        txn,
        invoiceId: invoice.id,
        oldNumber: null,
        newNumber: invoice.numero,
        source: InvoiceNumberChangeSource.createInvoice,
      );
      await txn.update(
        'gigs',
        {
          'invoice_id': invoice.id,
          'status': GigStatus.facturado.dbValue,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [invoice.gigId],
      );
    });
  }

  Future<void> update(Invoice invoice) async {
    final db = await DatabaseHelper.instance.database;
    final existingRows = await db.query(
      'invoices',
      columns: ['numero'],
      where: 'id = ?',
      whereArgs: [invoice.id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final currentNumber = existingRows.first['numero'] as int;
      if (currentNumber != invoice.numero) {
        throw StateError(
          'Cambio de número no permitido desde edición normal. '
          'Usa la reenumeración manual.',
        );
      }
    }
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

  Future<void> updateDriveMetadata({
    required String id,
    required String driveFileId,
    required String? driveFileUrl,
    required DateTime driveSyncedAt,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'invoices',
      {
        'drive_file_id': driveFileId,
        'drive_file_url': driveFileUrl,
        'drive_synced_at': driveSyncedAt.toIso8601String(),
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
          'status': GigStatus.confirmado.dbValue,
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

  Future<ManualRenumberResult> renumberInvoicesManually({
    required int fiscalYear,
    required Map<String, int> newNumbersByInvoiceId,
    String? userId,
    String? reason,
  }) async {
    if (newNumbersByInvoiceId.isEmpty) {
      throw StateError('No hay facturas para reenumerar.');
    }

    final targetIds = newNumbersByInvoiceId.keys.toList(growable: false);
    final targetNumbers = newNumbersByInvoiceId.values.toList(growable: false);
    for (final number in targetNumbers) {
      if (number <= 0) {
        throw StateError(
          'Todos los nuevos números deben ser enteros positivos.',
        );
      }
    }
    if (targetNumbers.toSet().length != targetNumbers.length) {
      throw StateError('Hay números duplicados en la nueva numeración.');
    }

    final db = await DatabaseHelper.instance.database;
    return db.transaction((txn) async {
      final placeholdersIds = List.filled(targetIds.length, '?').join(',');
      final rows = await txn.rawQuery('''
        SELECT *
        FROM invoices
        WHERE id IN ($placeholdersIds)
          AND deleted_at IS NULL
        ''', targetIds);

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

      final placeholdersNumbers = List.filled(
        targetNumbers.length,
        '?',
      ).join(',');
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
          {'numero': -9000000 - i, 'updated_at': now, 'number_locked': 0},
          where: 'id = ?',
          whereArgs: [targetIds[i]],
        );
      }

      for (final id in targetIds) {
        final newNumber = newNumbersByInvoiceId[id]!;
        await txn.update(
          'invoices',
          {'numero': newNumber, 'updated_at': now, 'number_locked': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      final updatedRows = await txn.rawQuery('''
        SELECT *
        FROM invoices
        WHERE id IN ($placeholdersIds)
        ''', targetIds);
      final updatedInvoices = updatedRows
          .map((row) => Invoice.fromMap(row))
          .toList(growable: false);
      final hasTemporaryNumber = updatedInvoices.any(
        (invoice) => invoice.numero <= 0,
      );
      if (hasTemporaryNumber) {
        throw StateError(
          'Error crítico: la reenumeración dejó números temporales.',
        );
      }

      final changes = <ManualRenumberChange>[];
      for (final updated in updatedInvoices) {
        final oldNumber = oldById[updated.id];
        if (oldNumber == null) continue;
        if (oldNumber != updated.numero) {
          await _recordInvoiceNumberChange(
            txn,
            invoiceId: updated.id,
            oldNumber: oldNumber,
            newNumber: updated.numero,
            source: InvoiceNumberChangeSource.manualRenumber,
            userId: userId,
            reason: reason,
          );
        }
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

  Future<void> updateInvoiceNumber({
    required String invoiceId,
    required int newNumber,
    required String source,
    String? reason,
    String? userId,
  }) async {
    if (!InvoiceNumberChangeSource.allowed.contains(source)) {
      _logBlockedNumberChange(
        origin: source,
        invoiceId: invoiceId,
        oldNumber: null,
        attemptedNumber: newNumber,
      );
      throw StateError('Origen no autorizado para cambiar número de factura.');
    }
    if (newNumber <= 0) {
      throw StateError('El nuevo número debe ser positivo.');
    }

    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'invoices',
        columns: ['numero', 'number_locked'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [invoiceId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Factura no encontrada para cambiar número.');
      }

      final oldNumber = rows.first['numero'] as int;
      final locked = (rows.first['number_locked'] as int? ?? 1) == 1;
      if (oldNumber == newNumber) return;
      if (locked && source != InvoiceNumberChangeSource.manualRenumber) {
        _logBlockedNumberChange(
          origin: source,
          invoiceId: invoiceId,
          oldNumber: oldNumber,
          attemptedNumber: newNumber,
        );
        throw StateError(
          'Factura bloqueada: solo reenumeración manual puede cambiar número.',
        );
      }

      await txn.update(
        'invoices',
        {
          'numero': newNumber,
          'updated_at': DateTime.now().toIso8601String(),
          'number_locked': 1,
        },
        where: 'id = ?',
        whereArgs: [invoiceId],
      );
      await _recordInvoiceNumberChange(
        txn,
        invoiceId: invoiceId,
        oldNumber: oldNumber,
        newNumber: newNumber,
        source: source,
        reason: reason,
        userId: userId,
      );
    });
  }

  Future<void> _recordInvoiceNumberChange(
    DatabaseExecutor db, {
    required String invoiceId,
    required int? oldNumber,
    required int newNumber,
    required String source,
    String? reason,
    String? userId,
  }) async {
    if (!InvoiceNumberChangeSource.allowed.contains(source)) {
      throw StateError('Origen no autorizado para auditar número de factura.');
    }
    await db.insert('invoice_number_changes', {
      'id': const Uuid().v4(),
      'invoice_id': invoiceId,
      'user_id': userId,
      'old_number': oldNumber,
      'new_number': newNumber,
      'source': source,
      'reason': reason,
      'created_at': DateTime.now().toIso8601String(),
    });
    debugPrint(
      '[InvoiceNumber] invoice_id=$invoiceId old_number=$oldNumber '
      'new_number=$newNumber source=$source reason=$reason',
    );
  }

  void _logBlockedNumberChange({
    required String origin,
    required String invoiceId,
    required int? oldNumber,
    required int attemptedNumber,
  }) {
    debugPrint(
      '[InvoiceNumber][CRITICAL] cambio bloqueado origin=$origin '
      'invoice_id=$invoiceId old_number=$oldNumber attempted=$attemptedNumber',
    );
    debugPrintStack(stackTrace: StackTrace.current);
  }
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
