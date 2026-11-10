import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/fechas_libres.dart';
import 'package:misbolos/models/gig.dart';

Gig _bolo(DateTime fecha, {GigStatus status = GigStatus.confirmado}) =>
    Gig(fecha: fecha, clientId: 'cliente', status: status);

/// Lunes a domingo.
const _lunes = DateTime.monday;
const _jueves = DateTime.thursday;
const _viernes = DateTime.friday;
const _sabado = DateTime.saturday;
const _domingo = DateTime.sunday;

List<int> _dias(List<DateTime> fechas) => fechas.map((f) => f.day).toList();

void main() {
  // Octubre de 2026 empieza en jueves y acaba en sábado.
  final hoyOctubre = DateTime(2026, 10, 1);

  group('diaClave', () {
    test('normaliza a UTC sin horas', () {
      expect(diaClave(DateTime(2026, 10, 2, 23, 59)), DateTime.utc(2026, 10, 2));
      expect(diaClave(DateTime.utc(2026, 10, 2, 5)), DateTime.utc(2026, 10, 2));
    });

    test('dos horas distintas del mismo día dan la misma clave', () {
      expect(
        diaClave(DateTime(2026, 10, 2, 0, 1)),
        diaClave(DateTime(2026, 10, 2, 23, 58)),
      );
    });
  });

  group('ocupacionPorDia', () {
    test('un bolo ocupa el día entero', () {
      final ocupacion = ocupacionPorDia([_bolo(DateTime(2026, 10, 2))]);
      expect(ocupacion[DateTime.utc(2026, 10, 2)], OcupacionDia.completa);
      expect(ocupacion[DateTime.utc(2026, 10, 2)]!.estaLibre, isFalse);
    });

    test('un bolo cancelado no ocupa', () {
      final ocupacion = ocupacionPorDia([
        _bolo(DateTime(2026, 10, 2), status: GigStatus.cancelado),
      ]);
      expect(ocupacion, isEmpty);
    });

    test('los estados privados sí ocupan', () {
      for (final status in [
        GigStatus.confirmadoB,
        GigStatus.realizadoB,
        GigStatus.cobradoB,
        GigStatus.facturado,
        GigStatus.cobrado,
      ]) {
        final ocupacion = ocupacionPorDia([
          _bolo(DateTime(2026, 10, 2), status: status),
        ]);
        expect(
          ocupacion[DateTime.utc(2026, 10, 2)]?.estaLibre,
          isFalse,
          reason: 'el estado $status debería ocupar',
        );
      }
    });

    test('dos bolos del mismo día a horas distintas ocupan un solo día', () {
      final ocupacion = ocupacionPorDia([
        _bolo(DateTime(2026, 10, 2, 18, 30)),
        _bolo(DateTime(2026, 10, 2, 23, 45)),
      ]);
      expect(ocupacion.length, 1);
      expect(ocupacion[DateTime.utc(2026, 10, 2)], OcupacionDia.completa);
    });

    test('un bolo cerca de medianoche cae en su propio día', () {
      final ocupacion = ocupacionPorDia([
        _bolo(DateTime(2026, 10, 2, 23, 59)),
        _bolo(DateTime(2026, 10, 3, 0, 1)),
      ]);
      expect(ocupacion.keys.toSet(), {
        DateTime.utc(2026, 10, 2),
        DateTime.utc(2026, 10, 3),
      });
    });

    test('un bolo cancelado no libera el día si hay otro bolo', () {
      final ocupacion = ocupacionPorDia([
        _bolo(DateTime(2026, 10, 2), status: GigStatus.cancelado),
        _bolo(DateTime(2026, 10, 2)),
      ]);
      expect(ocupacion[DateTime.utc(2026, 10, 2)]!.estaLibre, isFalse);
    });
  });

  group('diasLibres: patrones de días de la semana', () {
    test('viernes y sábado de octubre de 2026', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {_viernes, _sabado},
        hoy: hoyOctubre,
      );
      expect(_dias(libres), [2, 3, 9, 10, 16, 17, 23, 24, 30, 31]);
    });

    test('de jueves a domingo', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {_jueves, _viernes, _sabado, _domingo},
        hoy: hoyOctubre,
      );
      expect(_dias(libres).take(4), [1, 2, 3, 4]);
      expect(_dias(libres).last, 31);
    });

    test('sin días marcados no hay fechas libres', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {},
        hoy: hoyOctubre,
      );
      expect(libres, isEmpty);
    });
  });

  group('diasLibres: retoques manuales', () {
    test('un día añadido entra aunque no sea del patrón', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {_viernes},
        anadidos: {DateTime(2026, 10, 12)}, // lunes, festivo
        hoy: hoyOctubre,
      );
      expect(_dias(libres), contains(12));
    });

    test('un día quitado no entra aunque sea del patrón', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {_viernes, _sabado},
        quitados: {DateTime(2026, 10, 9)},
        hoy: hoyOctubre,
      );
      expect(_dias(libres), isNot(contains(9)));
      expect(_dias(libres), contains(10));
    });

    test('quitar manda sobre añadir', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {},
        anadidos: {DateTime(2026, 10, 12)},
        quitados: {DateTime(2026, 10, 12)},
        hoy: hoyOctubre,
      );
      expect(libres, isEmpty);
    });

    test('los retoques se normalizan igual que las claves', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {},
        anadidos: {DateTime(2026, 10, 12, 21, 30)},
        hoy: hoyOctubre,
      );
      expect(_dias(libres), [12]);
    });
  });

  group('diasLibres: ocupación', () {
    test('un día con bolo no sale', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {_viernes, _sabado},
        ocupacion: ocupacionPorDia([_bolo(DateTime(2026, 10, 9, 22))]),
        hoy: hoyOctubre,
      );
      expect(_dias(libres), isNot(contains(9)));
      expect(_dias(libres), contains(10));
    });

    test('un día con bolo cancelado sí sale', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {_viernes},
        ocupacion: ocupacionPorDia([
          _bolo(DateTime(2026, 10, 9), status: GigStatus.cancelado),
        ]),
        hoy: hoyOctubre,
      );
      expect(_dias(libres), contains(9));
    });

    test('un día añadido a mano pero ocupado no sale', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {},
        anadidos: {DateTime(2026, 10, 12)},
        ocupacion: ocupacionPorDia([_bolo(DateTime(2026, 10, 12))]),
        hoy: hoyOctubre,
      );
      expect(libres, isEmpty);
    });
  });

  group('diasLibres: días pasados', () {
    test('en el mes actual no salen los días anteriores a hoy', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {_viernes, _sabado},
        hoy: DateTime(2026, 10, 15),
      );
      expect(_dias(libres), [16, 17, 23, 24, 30, 31]);
    });

    test('hoy sí sale si está marcado y libre', () {
      final libres = diasLibres(
        year: 2026,
        month: 10,
        diasSemana: const {_viernes},
        hoy: DateTime(2026, 10, 16, 23, 30),
      );
      expect(_dias(libres).first, 16);
    });

    test('un mes futuro sale entero', () {
      final libres = diasLibres(
        year: 2026,
        month: 11,
        diasSemana: const {_domingo},
        hoy: DateTime(2026, 10, 15),
      );
      expect(_dias(libres), [1, 8, 15, 22, 29]);
    });
  });

  group('diasLibres: límites del mes', () {
    test('un mes que empieza en domingo y acaba en domingo', () {
      // Marzo de 2026: del domingo 1 al martes 31.
      final libres = diasLibres(
        year: 2026,
        month: 3,
        diasSemana: const {_domingo},
        hoy: DateTime(2026, 3, 1),
      );
      expect(_dias(libres), [1, 8, 15, 22, 29]);
    });

    test('un mes que empieza en lunes', () {
      // Junio de 2026 empieza en lunes.
      final libres = diasLibres(
        year: 2026,
        month: 6,
        diasSemana: const {_lunes},
        hoy: DateTime(2026, 6, 1),
      );
      expect(_dias(libres), [1, 8, 15, 22, 29]);
    });

    test('febrero de un año no bisiesto llega hasta el 28', () {
      final libres = diasLibres(
        year: 2026,
        month: 2,
        diasSemana: const {_sabado},
        hoy: DateTime(2026, 2, 1),
      );
      expect(_dias(libres), [7, 14, 21, 28]);
    });

    test('febrero de un año bisiesto llega hasta el 29', () {
      // 2028 es bisiesto y el 29 de febrero cae en martes.
      final libres = diasLibres(
        year: 2028,
        month: 2,
        diasSemana: const {DateTime.tuesday},
        hoy: DateTime(2028, 2, 1),
      );
      expect(_dias(libres), [1, 8, 15, 22, 29]);
    });

    test('diciembre no se desborda al año siguiente', () {
      final libres = diasLibres(
        year: 2026,
        month: 12,
        diasSemana: const {_jueves},
        hoy: DateTime(2026, 12, 1),
      );
      expect(_dias(libres), [3, 10, 17, 24, 31]);
      expect(libres.every((f) => f.month == 12), isTrue);
    });
  });

  group('mesInicial', () {
    test('sin fecha abre el mes actual', () {
      expect(
        mesInicial(hoy: DateTime(2026, 11, 10)),
        DateTime.utc(2026, 11, 1),
      );
    });

    test('una fecha del mes actual abre ese mes', () {
      expect(
        mesInicial(fecha: DateTime(2026, 11, 25), hoy: DateTime(2026, 11, 10)),
        DateTime.utc(2026, 11, 1),
      );
    });

    test('una fecha futura abre su mes', () {
      expect(
        mesInicial(fecha: DateTime(2027, 3, 4), hoy: DateTime(2026, 11, 10)),
        DateTime.utc(2027, 3, 1),
      );
    });

    test('un mes pasado abre el mes actual', () {
      expect(
        mesInicial(fecha: DateTime(2026, 9, 20), hoy: DateTime(2026, 11, 10)),
        DateTime.utc(2026, 11, 1),
      );
    });

    test('un mes pasado de otro año abre el mes actual', () {
      expect(
        mesInicial(fecha: DateTime(2025, 12, 31), hoy: DateTime(2026, 11, 10)),
        DateTime.utc(2026, 11, 1),
      );
    });

    test('un día pasado del mes actual abre el mes actual, no lo descarta', () {
      expect(
        mesInicial(fecha: DateTime(2026, 11, 1), hoy: DateTime(2026, 11, 10)),
        DateTime.utc(2026, 11, 1),
      );
    });
  });
}
