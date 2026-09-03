import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:misbolos/database/database_helper.dart';
import 'package:misbolos/models/gig.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/repositories/gig_repository.dart';
import 'package:misbolos/repositories/invoice_repository.dart';

void main() {
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dbPath = p.join(await getDatabasesPath(), 'misbolos_guest.db');
    await DatabaseHelper.instance.close();
    await deleteDatabase(dbPath);
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await deleteDatabase(dbPath);
  });

  test(
    'la numeración manual sobrevive a recargas ordenadas por fecha',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('clients', {
        'id': 'client-1',
        'nombre': 'Cliente',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });
      for (final id in ['gig-early', 'gig-late']) {
        await db.insert('gigs', {
          'id': id,
          'fecha': DateTime(2026, 1, 1).toIso8601String(),
          'client_id': 'client-1',
          'facturable': 1,
          'status': 'pendiente',
          'created_at': DateTime(2026).toIso8601String(),
        });
      }

      await InvoiceRepository.instance.insert(
        _invoice('inv-early', 10, DateTime(2026, 1, 10), 'gig-early'),
      );
      await InvoiceRepository.instance.insert(
        _invoice('inv-late', 20, DateTime(2026, 2, 10), 'gig-late'),
      );

      await InvoiceRepository.instance.renumberInvoicesManually(
        fiscalYear: 2026,
        newNumbersByInvoiceId: const {'inv-early': 2, 'inv-late': 1},
      );

      final reloaded = await InvoiceRepository.instance.getAll();
      final byId = {for (final invoice in reloaded) invoice.id: invoice.numero};
      expect(byId['inv-early'], 2);
      expect(byId['inv-late'], 1);

      final syncedEarly = (await InvoiceRepository.instance.getById(
        'inv-early',
      ))!.copyWith(status: InvoiceStatus.enviada);
      final syncedLate = (await InvoiceRepository.instance.getById(
        'inv-late',
      ))!.copyWith(status: InvoiceStatus.pagada);
      await InvoiceRepository.instance.upsert(syncedEarly);
      await InvoiceRepository.instance.upsert(syncedLate);

      expect(
        (await InvoiceRepository.instance.getById('inv-early'))?.numero,
        2,
      );
      expect((await InvoiceRepository.instance.getById('inv-late'))?.numero, 1);
    },
  );

  test(
    'renumberInvoicesManually permite intercambiar 1 y 2 sin conflicto',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('clients', {
        'id': 'client-1',
        'nombre': 'Cliente',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });
      for (final id in ['gig-a', 'gig-b']) {
        await db.insert('gigs', {
          'id': id,
          'fecha': DateTime(2026, 1, 1).toIso8601String(),
          'client_id': 'client-1',
          'facturable': 1,
          'status': 'pendiente',
          'created_at': DateTime(2026).toIso8601String(),
        });
      }

      await InvoiceRepository.instance.insert(
        _invoice('inv-a', 1, DateTime(2026, 1, 10), 'gig-a'),
      );
      await InvoiceRepository.instance.insert(
        _invoice('inv-b', 2, DateTime(2026, 1, 11), 'gig-b'),
      );

      final result = await InvoiceRepository.instance.renumberInvoicesManually(
        fiscalYear: 2026,
        newNumbersByInvoiceId: const {'inv-a': 2, 'inv-b': 1},
      );

      expect(result.changes.length, 2);
      expect((await InvoiceRepository.instance.getById('inv-a'))?.numero, 2);
      expect((await InvoiceRepository.instance.getById('inv-b'))?.numero, 1);
    },
  );

  test('update normal no puede cambiar el número fiscal', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('clients', {
      'id': 'client-1',
      'nombre': 'Cliente',
      'created_at': DateTime(2026).toIso8601String(),
      'updated_at': DateTime(2026).toIso8601String(),
    });
    await db.insert('gigs', {
      'id': 'gig-a',
      'fecha': DateTime(2026, 1, 1).toIso8601String(),
      'client_id': 'client-1',
      'facturable': 1,
      'status': 'pendiente',
      'created_at': DateTime(2026).toIso8601String(),
    });

    final invoice = _invoice('inv-a', 7, DateTime(2026, 1, 10), 'gig-a');
    await InvoiceRepository.instance.insert(invoice);

    expect(
      () => InvoiceRepository.instance.update(invoice.copyWith(numero: 8)),
      throwsStateError,
    );
    expect((await InvoiceRepository.instance.getById('inv-a'))?.numero, 7);
  });

  test(
    'renumberInvoicesManually reenumera 20 facturas sin devolver temporales',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('clients', {
        'id': 'client-1',
        'nombre': 'Cliente',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });

      final newNumbers = <String, int>{};
      for (var i = 1; i <= 20; i++) {
        final gigId = 'gig-$i';
        final invoiceId = 'inv-$i';
        await db.insert('gigs', {
          'id': gigId,
          'fecha': DateTime(2026, 1, i).toIso8601String(),
          'client_id': 'client-1',
          'facturable': 1,
          'status': 'pendiente',
          'created_at': DateTime(2026).toIso8601String(),
        });
        await InvoiceRepository.instance.insert(
          _invoice(invoiceId, i, DateTime(2026, 1, i), gigId),
        );
        newNumbers[invoiceId] = 21 - i;
      }

      final result = await InvoiceRepository.instance.renumberInvoicesManually(
        fiscalYear: 2026,
        newNumbersByInvoiceId: newNumbers,
      );

      expect(result.updatedInvoices, hasLength(20));
      expect(
        result.updatedInvoices.every((invoice) => invoice.numero > 0),
        true,
      );
      final stored = await InvoiceRepository.instance.getByFiscalYear(2026);
      expect(stored, hasLength(20));
      expect(stored.every((invoice) => invoice.numero > 0), true);
      for (final invoice in stored) {
        expect(invoice.numero, newNumbers[invoice.id]);
      }
    },
  );

  test('upsert rechaza números temporales', () async {
    expect(
      () => InvoiceRepository.instance.upsert(
        _invoice('inv-temp', -1, DateTime(2026, 1, 10), 'gig-temp'),
      ),
      throwsStateError,
    );
  });

  test(
    'upsert genérico conserva número local frente a remoto antiguo',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('clients', {
        'id': 'client-1',
        'nombre': 'Cliente',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });
      await db.insert('gigs', {
        'id': 'gig-a',
        'fecha': DateTime(2026, 1, 1).toIso8601String(),
        'client_id': 'client-1',
        'facturable': 1,
        'status': 'pendiente',
        'created_at': DateTime(2026).toIso8601String(),
      });

      final invoice = _invoice('inv-a', 5, DateTime(2026, 1, 30), 'gig-a');
      await InvoiceRepository.instance.insert(invoice);
      await InvoiceRepository.instance.upsert(
        invoice.copyWith(numero: 1, updatedAt: DateTime(2026, 2)),
      );

      expect((await InvoiceRepository.instance.getById('inv-a'))?.numero, 5);
    },
  );

  test(
    'upsert solo acepta cambio de número con origen manual auditado',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('clients', {
        'id': 'client-1',
        'nombre': 'Cliente',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });
      await db.insert('gigs', {
        'id': 'gig-a',
        'fecha': DateTime(2026, 1, 1).toIso8601String(),
        'client_id': 'client-1',
        'facturable': 1,
        'status': 'pendiente',
        'created_at': DateTime(2026).toIso8601String(),
      });

      final invoice = _invoice('inv-a', 5, DateTime(2026, 1, 30), 'gig-a');
      await InvoiceRepository.instance.insert(invoice);
      await InvoiceRepository.instance.upsert(
        invoice.copyWith(numero: 9, updatedAt: DateTime(2026, 2)),
        allowedNumberChangeSource: InvoiceNumberChangeSource.manualRenumber,
      );

      expect((await InvoiceRepository.instance.getById('inv-a'))?.numero, 9);
      final auditRows = await db.query(
        'invoice_number_changes',
        where: 'invoice_id = ? AND old_number = ? AND new_number = ?',
        whereArgs: ['inv-a', 5, 9],
      );
      expect(auditRows, hasLength(1));
    },
  );

  test(
    'facturas desordenadas mantienen número tras upsert e import repair',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('clients', {
        'id': 'client-1',
        'nombre': 'Cliente',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });
      final fixtures = [
        ('gig-a', 'inv-a', DateTime(2026, 1, 30), 5),
        ('gig-b', 'inv-b', DateTime(2026, 1, 3), 1),
        ('gig-c', 'inv-c', DateTime(2026, 3, 7), 2),
      ];

      for (final fixture in fixtures) {
        await db.insert('gigs', {
          'id': fixture.$1,
          'fecha': fixture.$3.toIso8601String(),
          'client_id': 'client-1',
          'facturable': 1,
          'status': 'pendiente',
          'created_at': DateTime(2026).toIso8601String(),
        });
        await InvoiceRepository.instance.insert(
          _invoice(fixture.$2, fixture.$4, fixture.$3, fixture.$1),
        );
      }

      await InvoiceRepository.instance.upsert(
        _invoice(
          'inv-a',
          1,
          DateTime(2026, 1, 30),
          'gig-a',
        ).copyWith(updatedAt: DateTime(2026, 4)),
      );
      await InvoiceRepository.instance.updateStatus(
        'inv-b',
        InvoiceStatus.enviada,
      );

      expect((await InvoiceRepository.instance.getById('inv-a'))?.numero, 5);
      expect((await InvoiceRepository.instance.getById('inv-b'))?.numero, 1);
      expect((await InvoiceRepository.instance.getById('inv-c'))?.numero, 2);
    },
  );

  test(
    'una factura borrada no bloquea la numeración de nuevas facturas activas',
    () async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('clients', {
        'id': 'client-1',
        'nombre': 'Cliente',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });

      await GigRepository.instance.insert(
        Gig(
          id: 'gig-prev',
          fecha: DateTime(2026, 1, 5),
          clientId: 'client-1',
          status: GigStatus.confirmado,
        ),
      );
      await InvoiceRepository.instance.insert(
        _invoice('inv-prev', 33, DateTime(2026, 1, 5), 'gig-prev'),
      );

      await GigRepository.instance.insert(
        Gig(
          id: 'gig-a',
          fecha: DateTime(2026, 1, 10),
          clientId: 'client-1',
          status: GigStatus.confirmado,
        ),
      );
      await InvoiceRepository.instance.insert(
        _invoice('inv-a', 34, DateTime(2026, 1, 10), 'gig-a'),
      );
      await InvoiceRepository.instance.deleteAndUnlinkGig('inv-a');

      await GigRepository.instance.insert(
        Gig(
          id: 'gig-b',
          fecha: DateTime(2026, 2, 10),
          clientId: 'client-1',
          status: GigStatus.facturado,
        ),
      );

      final created = await InvoiceRepository.instance.getByGigId('gig-b');
      expect(created, isNotNull);
      expect(created?.numero, 34);
    },
  );

  test('al borrar la factura se libera el bolo para generar otra', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('clients', {
      'id': 'client-1',
      'nombre': 'Cliente',
      'created_at': DateTime(2026).toIso8601String(),
      'updated_at': DateTime(2026).toIso8601String(),
    });

    await GigRepository.instance.insert(
      Gig(
        id: 'gig-a',
        fecha: DateTime(2026, 1, 10),
        clientId: 'client-1',
        status: GigStatus.confirmado,
      ),
    );
    await InvoiceRepository.instance.insertAndLinkGig(
      _invoice('inv-a', 34, DateTime(2026, 1, 10), 'gig-a'),
    );

    await InvoiceRepository.instance.deleteAndUnlinkGig('inv-a');

    final gig = await GigRepository.instance.getById('gig-a');
    final invoice = await InvoiceRepository.instance.getByGigId('gig-a');

    expect(gig?.status, GigStatus.confirmado);
    expect(gig?.invoiceId, isNull);
    expect(invoice, isNull);
  });
}

Invoice _invoice(String id, int number, DateTime date, String gigId) {
  return Invoice(
    id: id,
    numero: number,
    fecha: date,
    clientId: 'client-1',
    gigId: gigId,
    items: [
      InvoiceLineItem(cantidad: 1, descripcion: 'Bolo', precioUnitario: 100),
    ],
    subtotal: 100,
    ivaAmount: 21,
    total: 121,
    createdAt: date,
  );
}
