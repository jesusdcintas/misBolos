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

  group('el mensaje de por qué no vale el número', () {
    test('dice de quién es el número cuando está ocupado', () async {
      await _crearFactura('inv-27', 27, DateTime(2026, 5, 1));

      await expectLater(
        () => _repo.fijarProximoNumero(year: 2026, numero: 27),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'mensaje',
            'El número 27 ya es de la factura F-2026-0027.',
          ),
        ),
      );
    });

    test('si está libre pero hay posteriores, lo explica', () async {
      await _crearFactura('inv-30', 30, DateTime(2026, 5, 1));

      await expectLater(
        () => _repo.fijarProximoNumero(year: 2026, numero: 27),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'mensaje',
            'No puedes usar el 27 porque ya existe la F-2026-0030: la '
                'numeración no puede retroceder. Elige uno mayor que 30.',
          ),
        ),
      );
    });
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

    test('también se puede borrar una del medio, y queda un hueco', () async {
      final primera = await _crearFactura('inv-1', 1, DateTime(2026, 2, 1));
      await _crearFactura('inv-2', 2, DateTime(2026, 3, 1));

      await _repo.deleteAndUnlinkGig(primera.id);

      expect((await _repo.getById(primera.id))?.deletedAt, isNotNull);
      // El hueco del 1 se queda: la numeración no retrocede sola.
      expect(await _repo.getNextNumberForYear(2026), 3);
    });

    test('saber cuál es la última de la serie', () async {
      final primera = await _crearFactura('inv-1', 1, DateTime(2026, 2, 1));
      final segunda = await _crearFactura('inv-2', 2, DateTime(2026, 3, 1));

      expect(await _repo.esUltimaDeLaSerie(primera), isFalse);
      expect(await _repo.esUltimaDeLaSerie(segunda), isTrue);
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

  group('volver a facturar un bolo', () {
    test(
      'tras borrar su factura, el bolo se puede facturar otra vez',
      () async {
        // Crear el bolo y su factura, y dejarla emitida.
        await GigRepository.instance.insert(
          Gig(
            id: 'gig-1',
            fecha: DateTime(2026, 4, 10),
            clientId: 'client-1',
            status: GigStatus.confirmado,
          ),
        );
        final primera = _factura('inv-1', 1, DateTime(2026, 4, 10), 'gig-1');
        await _repo.insertAndLinkGig(primera);
        await _repo.updateStatus('inv-1', InvoiceStatus.enviada);

        var bolo = await GigRepository.instance.getById('gig-1');
        expect(bolo?.status, GigStatus.facturado);
        expect(bolo?.invoiceId, 'inv-1');

        // Borrarla devuelve el bolo a confirmado y sin factura.
        await _repo.deleteAndUnlinkGig('inv-1');
        bolo = await GigRepository.instance.getById('gig-1');
        expect(bolo?.status, GigStatus.confirmado);
        expect(bolo?.invoiceId, isNull);

        // Y se puede volver a facturar, reusando el número liberado.
        expect(await _repo.getNextNumberForYear(2026), 1);
        final segunda = _factura('inv-2', 1, DateTime(2026, 4, 10), 'gig-1');
        await _repo.insertAndLinkGig(segunda);

        bolo = await GigRepository.instance.getById('gig-1');
        expect(bolo?.status, GigStatus.facturado);
        expect(bolo?.invoiceId, 'inv-2');
        expect((await _repo.getByGigId('gig-1'))?.id, 'inv-2');
      },
    );

    test('un bolo que apunta a una factura borrada se suelta', () async {
      // El enlace puede sobrevivir a una sincronización: pasara como pasara,
      // el bolo tiene que poder volver a facturarse.
      final factura = await _crearFactura('inv-1', 1, DateTime(2026, 4, 10));
      await _repo.delete(factura.id);
      await GigRepository.instance.linkInvoice('gig-inv-1', factura.id);

      var bolo = await GigRepository.instance.getById('gig-inv-1');
      expect(bolo?.invoiceId, factura.id, reason: 'parte del enlace colgando');

      await GigRepository.instance.desvincularFactura('gig-inv-1');

      bolo = await GigRepository.instance.getById('gig-inv-1');
      expect(bolo?.invoiceId, isNull);
      expect(bolo?.status, GigStatus.confirmado);
    });

    test('un bolo privado vuelve a su estado privado al soltarla', () async {
      await GigRepository.instance.insert(
        Gig(
          id: 'gig-privado',
          fecha: DateTime(2026, 4, 10),
          clientId: 'client-1',
          facturable: false,
          status: GigStatus.confirmadoB,
        ),
      );
      await GigRepository.instance.linkInvoice('gig-privado', 'inv-fantasma');

      await GigRepository.instance.desvincularFactura('gig-privado');

      final bolo = await GigRepository.instance.getById('gig-privado');
      expect(bolo?.invoiceId, isNull);
      expect(bolo?.status, GigStatus.confirmadoB);
    });
  });

  group('el bolo al borrar su factura', () {
    test('suelta la factura y vuelve a confirmado', () async {
      final factura = await _crearFactura('inv-1', 1, DateTime(2026, 2, 1));

      await _repo.deleteAndUnlinkGig(factura.id);

      final bolo = await GigRepository.instance.getById('gig-inv-1');
      expect(bolo?.invoiceId, isNull);
      expect(bolo?.status, GigStatus.confirmado);
    });

    test('un bolo privado vuelve a su confirmado privado', () async {
      await GigRepository.instance.insert(
        Gig(
          id: 'gig-privado',
          fecha: DateTime(2026, 2, 1),
          clientId: 'client-1',
          facturable: false,
          status: GigStatus.confirmadoB,
        ),
      );
      final factura = _factura(
        'inv-privada',
        1,
        DateTime(2026, 2, 1),
        'gig-privado',
      );
      await _repo.insert(factura);

      await _repo.deleteAndUnlinkGig(factura.id);

      final bolo = await GigRepository.instance.getById('gig-privado');
      expect(bolo?.invoiceId, isNull);
      expect(bolo?.status, GigStatus.confirmadoB);
    });
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

    test('local ya subido y nube más reciente: gana la nube', () async {
      // El Mac fija 30 y lo sube: su fecha pasa a ser la del servidor.
      await _repo.fijarProximoNumero(year: 2026, numero: 30);
      await _contadores.adoptarFechaDelServidor(
        serie: 'F',
        fiscalYear: 2026,
        updatedAt: DateTime(2026, 11, 17, 19, 0),
      );

      // El simulador lo cambia después a 33: el servidor le pone su hora.
      await _contadores.fusionarDesdeNube(
        InvoiceCounter(
          serie: 'F',
          fiscalYear: 2026,
          nextNumber: 33,
          updatedAt: DateTime(2026, 11, 17, 19, 5),
        ),
      );

      expect(await _repo.getNextNumberForYear(2026), 33);
    });

    test('local ya subido y más reciente que la nube: gana el local', () async {
      await _repo.fijarProximoNumero(year: 2026, numero: 33);
      await _contadores.adoptarFechaDelServidor(
        serie: 'F',
        fiscalYear: 2026,
        updatedAt: DateTime(2026, 11, 17, 19, 5),
      );

      await _contadores.fusionarDesdeNube(
        InvoiceCounter(
          serie: 'F',
          fiscalYear: 2026,
          nextNumber: 30,
          updatedAt: DateTime(2026, 11, 17, 19, 0),
        ),
      );

      expect(await _repo.getNextNumberForYear(2026), 33);
    });

    test(
      'con el reloj del dispositivo adelantado se perdía el cambio',
      () async {
        // Sin adoptar la fecha del servidor, la fecha local era la del
        // dispositivo: un reloj adelantado ganaba siempre.
        await _repo.fijarProximoNumero(year: 2026, numero: 30);
        final local = await _contadores.get(serie: 'F', fiscalYear: 2026);
        expect(local, isNotNull);

        await _contadores.adoptarFechaDelServidor(
          serie: 'F',
          fiscalYear: 2026,
          updatedAt: DateTime(2026, 11, 17, 19, 0),
        );
        final trasSubir = await _contadores.get(serie: 'F', fiscalYear: 2026);

        expect(trasSubir?.nextNumber, 30, reason: 'el número no cambia');
        expect(trasSubir?.updatedAt, DateTime(2026, 11, 17, 19, 0));
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
