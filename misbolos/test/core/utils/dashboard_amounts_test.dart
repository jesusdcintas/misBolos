import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/dashboard_amounts.dart';

void main() {
  group('confirmadoSinFacturar', () {
    test('es lo que queda del previsto al quitar cobrado y pendiente', () {
      expect(
        confirmadoSinFacturar(
          totalPrevisto: 10000,
          cobrado: 4000,
          pendiente: 2500,
        ),
        3500,
      );
    });

    test('es 0 cuando todo está cobrado o pendiente', () {
      expect(
        confirmadoSinFacturar(
          totalPrevisto: 6500,
          cobrado: 4000,
          pendiente: 2500,
        ),
        0,
      );
    });

    test('nunca es negativo aunque los importes no cuadren', () {
      expect(
        confirmadoSinFacturar(
          totalPrevisto: 1000,
          cobrado: 4000,
          pendiente: 2500,
        ),
        0,
      );
    });

    test('un periodo vacío da 0', () {
      expect(
        confirmadoSinFacturar(totalPrevisto: 0, cobrado: 0, pendiente: 0),
        0,
      );
    });

    test('conserva los céntimos', () {
      expect(
        confirmadoSinFacturar(
          totalPrevisto: 3545.40,
          cobrado: 1000.15,
          pendiente: 500.25,
        ),
        closeTo(2045.00, 0.001),
      );
    });
  });

  group('reservaParaHacienda', () {
    test('suma el IVA repercutido y el IRPF que falta por ingresar', () {
      expect(
        reservaParaHacienda(ivaRepercutido: 2100, irpfAIngresar: 800),
        2900,
      );
    });

    test('no cuenta el IRPF ya retenido: si no queda nada, solo el IVA', () {
      expect(reservaParaHacienda(ivaRepercutido: 2100, irpfAIngresar: 0), 2100);
    });

    test('un periodo sin facturas da 0', () {
      expect(reservaParaHacienda(ivaRepercutido: 0, irpfAIngresar: 0), 0);
    });

    test('nunca es negativa', () {
      expect(
        reservaParaHacienda(ivaRepercutido: 0, irpfAIngresar: -500),
        0,
      );
    });

    test('conserva los céntimos', () {
      expect(
        reservaParaHacienda(ivaRepercutido: 744.53, irpfAIngresar: 212.72),
        closeTo(957.25, 0.001),
      );
    });
  });
}
