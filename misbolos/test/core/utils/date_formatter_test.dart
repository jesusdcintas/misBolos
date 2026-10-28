import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/date_formatter.dart';

void main() {
  group('DateFormatter.parseIsoDay', () {
    test('lee una fecha válida a medianoche local', () {
      final fecha = DateFormatter.parseIsoDay('2026-11-13');
      expect(fecha, DateTime(2026, 11, 13));
      expect(fecha!.hour, 0);
      expect(fecha.minute, 0);
      expect(fecha.second, 0);
      expect(fecha.isUtc, isFalse);
    });

    test('acepta fechas pasadas', () {
      expect(DateFormatter.parseIsoDay('2020-01-05'), DateTime(2020, 1, 5));
    });

    test('devuelve null si la fecha no llega', () {
      expect(DateFormatter.parseIsoDay(null), isNull);
    });

    test('devuelve null si la fecha está mal formada', () {
      expect(DateFormatter.parseIsoDay(''), isNull);
      expect(DateFormatter.parseIsoDay('13/11/2026'), isNull);
      expect(DateFormatter.parseIsoDay('2026-11'), isNull);
      expect(DateFormatter.parseIsoDay('2026-11-13T10:30:00'), isNull);
      expect(DateFormatter.parseIsoDay('hoy'), isNull);
    });

    test('devuelve null si el día no existe', () {
      expect(DateFormatter.parseIsoDay('2026-02-30'), isNull);
      expect(DateFormatter.parseIsoDay('2026-13-01'), isNull);
      expect(DateFormatter.parseIsoDay('2026-00-10'), isNull);
      expect(DateFormatter.parseIsoDay('2026-11-00'), isNull);
    });

    test('acepta el 29 de febrero en año bisiesto', () {
      expect(DateFormatter.parseIsoDay('2028-02-29'), DateTime(2028, 2, 29));
    });
  });

  group('DateFormatter.isoDay', () {
    test('formatea como yyyy-MM-dd', () {
      expect(DateFormatter.isoDay(DateTime(2026, 11, 13)), '2026-11-13');
      expect(DateFormatter.isoDay(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('descarta la hora al formatear', () {
      expect(
        DateFormatter.isoDay(DateTime(2026, 11, 13, 23, 59)),
        '2026-11-13',
      );
    });

    test('ida y vuelta normaliza a medianoche', () {
      final conHora = DateTime(2026, 11, 13, 18, 45);
      expect(
        DateFormatter.parseIsoDay(DateFormatter.isoDay(conHora)),
        DateTime(2026, 11, 13),
      );
    });
  });
}
