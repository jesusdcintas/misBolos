import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:misbolos/database/database_helper.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/repositories/invoice_repository.dart';

void main() {
  late String dbPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dbPath = p.join(await getDatabasesPath(), 'misbolos.db');
    await DatabaseHelper.instance.close();
    await deleteDatabase(dbPath);
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await deleteDatabase(dbPath);
  });

  test('renumberYear reenumera solo el año indicado desde 1', () async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('clients', {
      'id': 'client-1',
      'nombre': 'Cliente',
      'created_at': DateTime(2025).toIso8601String(),
      'updated_at': DateTime(2025).toIso8601String(),
    });
    for (final id in ['gig-2025-a', 'gig-2025-b', 'gig-2026']) {
      await db.insert('gigs', {
        'id': id,
        'fecha': id == 'gig-2026'
            ? DateTime(2026, 1, 1).toIso8601String()
            : DateTime(2025, 1, 1).toIso8601String(),
        'client_id': 'client-1',
        'facturable': 1,
        'status': 'pendiente',
        'created_at': DateTime(2025).toIso8601String(),
      });
    }

    await InvoiceRepository.instance.insert(
      _invoice('inv-2025-a', 2, DateTime(2025, 1, 10), 'gig-2025-a'),
    );
    await InvoiceRepository.instance.insert(
      _invoice('inv-2025-b', 1, DateTime(2025, 2, 10), 'gig-2025-b'),
    );
    await InvoiceRepository.instance.insert(
      _invoice('inv-2026', 1, DateTime(2026, 1, 10), 'gig-2026'),
    );

    final renumbered = await InvoiceRepository.instance.renumberYear(2025);

    expect(renumbered.map((invoice) => invoice.numero), [1, 2]);
    expect((await InvoiceRepository.instance.getById('inv-2025-a'))?.numero, 1);
    expect((await InvoiceRepository.instance.getById('inv-2025-b'))?.numero, 2);
    expect((await InvoiceRepository.instance.getById('inv-2026'))?.numero, 1);
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
