import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:misbolos/database/database_helper.dart';
import 'package:misbolos/models/gig.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/models/invoice_counter.dart';
import 'package:misbolos/repositories/gig_repository.dart';
import 'package:misbolos/repositories/invoice_counter_repository.dart';
import 'package:misbolos/repositories/invoice_repository.dart';

final _repo = InvoiceRepository.instance;
final _contadores = InvoiceCounterRepository.instance;

Invoice _factura(String id, int numero, DateTime fecha, String gigId) {
  return Invoice(
    id: id,
    numero: numero,
    fecha: fecha,
    clientId: 'client-1',
    gigId: gigId,
    items: [
      InvoiceLineItem(cantidad: 1, descripcion: 'Bolo', precioUnitario: 100),
    ],
    subtotal: 100,
    ivaAmount: 21,
    total: 121,
    createdAt: fecha,
  );
}

/// Crea el bolo y la factura, que van siempre de la mano.
Future<Invoice> _crearFactura(String id, int numero, DateTime fecha) async {
  final gigId = 'gig-$id';
  await GigRepository.instance.insert(
    Gig(
      id: gigId,
      fecha: fecha,
      clientId: 'client-1',
      status: GigStatus.confirmado,
    ),
  );
  final factura = _factura(id, numero, fecha, gigId);
  await _repo.insert(factura);
  return factura;
}

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
    final db = await DatabaseHelper.instance.database;
    await db.insert('clients', {
      'id': 'client-1',
      'nombre': 'Cliente',
      'created_at': DateTime(2026).toIso8601String(),
      'updated_at': DateTime(2026).toIso8601String(),
    });
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    await deleteDatabase(dbPath);
  });

  group('fijar el número de la siguiente factura', () {
    test('sin facturas, se puede fijar cualquiera', () async {
      await _repo.fijarProximoNumero(year: 2026, numero: 16);

      expect(await _repo.getNextNumberForYear(2026), 16);
    });

    test('no se puede fijar el número de una factura que ya existe', () async {
      await _crearFactura('inv-12', 12, DateTime(2026, 3, 1));

      await expectLater(
        () => _repo.fijarProximoNumero(year: 2026, numero: 12),
        throwsA(isA<StateError>()),
      );
      expect(await _repo.getNextNumberForYear(2026), 13);
    });

    test('tampoco uno menor', () async {
      await _crearFactura('inv-12', 12, DateTime(2026, 3, 1));

      await expectLater(
        () => _repo.fijarProximoNumero(year: 2026, numero: 5),
        throwsA(isA<StateError>()),
      );
    });

    test('uno mayor sí, y manda sobre el contar normal', () async {
      await _crearFactura('inv-12', 12, DateTime(2026, 3, 1));
      await _repo.fijarProximoNumero(year: 2026, numero: 50);

      expect(await _repo.getNextNumberForYear(2026), 50);
    });

    test('fijar 16 por error y corregirlo a 6 deja 6', () async {
      await _repo.fijarProximoNumero(year: 2026, numero: 16);
      await _repo.fijarProximoNumero(year: 2026, numero: 6);

      expect(await _repo.getNextNumberForYear(2026), 6);

      // Y sigue siendo 6 después de sincronizar, porque el cambio local es
      // más reciente que el que hubiera en la nube.
      await _contadores.fusionarDesdeNube(
        InvoiceCounter(
          serie: 'F',
          fiscalYear: 2026,
          nextNumber: 16,
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      expect(await _repo.getNextNumberForYear(2026), 6);
    });
  });

  group('borrar facturas', () {
    test('fijar 16, crear la 16 y borrarla devuelve el 16', () async {
      await _repo.fijarProximoNumero(year: 2026, numero: 16);
      final factura = await _crearFactura('inv-16', 16, DateTime(2026, 4, 1));
      expect(await _repo.getNextNumberForYear(2026), 17);

      await _repo.deleteAndUnlinkGig(factura.id);

      expect(await _repo.getNextNumberForYear(2026), 16);
    });

    test('sin contador: crear la 1 y borrarla devuelve el 1', () async {
      expect(await _repo.getNextNumberForYear(2026), 1);
      final factura = await _crearFactura('inv-1', 1, DateTime(2026, 2, 1));
      expect(await _repo.getNextNumberForYear(2026), 2);

      await _repo.deleteAndUnlinkGig(factura.id);

      expect(await _repo.getNextNumberForYear(2026), 1);
    });

    test('solo se borra la última de la serie', () async {
      final primera = await _crearFactura('inv-1', 1, DateTime(2026, 2, 1));
      await _crearFactura('inv-2', 2, DateTime(2026, 3, 1));

      await expectLater(
        () => _repo.deleteAndUnlinkGig(primera.id),
        throwsA(isA<InvoiceNotLastException>()),
      );

      // Sigue ahí y la numeración no se mueve.
      expect((await _repo.getById(primera.id))?.deletedAt, isNull);
      expect(await _repo.getNextNumberForYear(2026), 3);
    });

    test(
      'el borrado que llega de otro dispositivo se aplica siempre',
      () async {
        final primera = await _crearFactura('inv-1', 1, DateTime(2026, 2, 1));
        await _crearFactura('inv-2', 2, DateTime(2026, 3, 1));

        // La vía de sincronización no pregunta: allí ya está borrada.
        await _repo.delete(primera.id);

        expect((await _repo.getById(primera.id))?.deletedAt, isNotNull);
        // El hueco queda, pero la numeración sigue sin retroceder.
        expect(await _repo.getNextNumberForYear(2026), 3);
      },
    );
  });

  group('cambio de año', () {
    test('cada año cuenta por su cuenta', () async {
      await _crearFactura('inv-2026', 7, DateTime(2026, 12, 20));

      expect(await _repo.getNextNumberForYear(2026), 8);
      expect(await _repo.getNextNumberForYear(2027), 1);
    });

    test('el contador de un año no afecta al siguiente', () async {
      await _repo.fijarProximoNumero(year: 2026, numero: 40);

      expect(await _repo.getNextNumberForYear(2026), 40);
      expect(await _repo.getNextNumberForYear(2027), 1);
    });
  });

  group('contador de la nube', () {
    test('si la nube es más reciente, gana la nube', () async {
      await _repo.fijarProximoNumero(year: 2026, numero: 6);

      await _contadores.fusionarDesdeNube(
        InvoiceCounter(
          serie: 'F',
          fiscalYear: 2026,
          nextNumber: 20,
          updatedAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );

      expect(await _repo.getNextNumberForYear(2026), 20);
    });

    test('si el local es más reciente, gana el local', () async {
      await _repo.fijarProximoNumero(year: 2026, numero: 6);

      await _contadores.fusionarDesdeNube(
        InvoiceCounter(
          serie: 'F',
          fiscalYear: 2026,
          nextNumber: 20,
          updatedAt: DateTime(2020),
        ),
      );

      expect(await _repo.getNextNumberForYear(2026), 6);
    });

    test(
      'un contador de la nube se aplica si en local no hay ninguno',
      () async {
        await _contadores.fusionarDesdeNube(
          InvoiceCounter(
            serie: 'F',
            fiscalYear: 2026,
            nextNumber: 30,
            updatedAt: DateTime(2026, 5, 1),
          ),
        );

        expect(await _repo.getNextNumberForYear(2026), 30);
      },
    );

    test('un contador nunca puede repetir un número ya usado', () async {
      await _crearFactura('inv-40', 40, DateTime(2026, 6, 1));

      // Aunque la nube traiga un número viejo y bajo.
      await _contadores.fusionarDesdeNube(
        InvoiceCounter(
          serie: 'F',
          fiscalYear: 2026,
          nextNumber: 5,
          updatedAt: DateTime.now().add(const Duration(minutes: 5)),
        ),
      );

      expect(await _repo.getNextNumberForYear(2026), 41);
    });
  });
}
