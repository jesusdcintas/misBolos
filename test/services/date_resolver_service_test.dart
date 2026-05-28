import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/services/date_resolver_service.dart';

void main() {
  group('DateResolverService', () {
    final now = DateTime(2026, 5, 28); // jueves

    test('resuelve viernes/sabado/domingo/lunes desde jueves', () {
      final service = DateResolverService.instance;
      expect(
        service.resolveExpression('viernes', now: now),
        DateTime(2026, 5, 29),
      );
      expect(
        service.resolveExpression('sábado', now: now),
        DateTime(2026, 5, 30),
      );
      expect(
        service.resolveExpression('domingo', now: now),
        DateTime(2026, 5, 31),
      );
      expect(
        service.resolveExpression('lunes', now: now),
        DateTime(2026, 6, 1),
      );
    });

    test('si el dia ya paso, usa semana siguiente', () {
      final service = DateResolverService.instance;
      expect(
        service.resolveExpression('jueves', now: now),
        DateTime(2026, 6, 4),
      );
      expect(
        service.resolveExpression('miércoles', now: now),
        DateTime(2026, 6, 3),
      );
    });
  });
}
