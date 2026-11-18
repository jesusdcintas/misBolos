import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/models/invoice.dart';
import 'package:misbolos/models/invoice_counter.dart';

InvoiceCounter _contador(int numero, DateTime cuando) => InvoiceCounter(
  serie: 'F',
  fiscalYear: 2026,
  nextNumber: numero,
  updatedAt: cuando,
);

void main() {
  group('el número que toca', () {
    test('sin contador, sigue la cuenta de las facturas', () {
      expect(proximoNumeroFactura(mayorUsado: 0), 1);
      expect(proximoNumeroFactura(mayorUsado: 15), 16);
    });

    test('el contador manda si va por delante', () {
      expect(proximoNumeroFactura(mayorUsado: 15, contadorFijado: 40), 40);
    });

    test('pero nunca repite un número ya usado', () {
      expect(proximoNumeroFactura(mayorUsado: 40, contadorFijado: 5), 41);
    });
  });

  group('qué número se puede fijar', () {
    test('uno mayor que el último usado', () {
      expect(sePuedeFijarNumero(16, mayorUsado: 15), isTrue);
    });

    test('ni el mismo ni uno menor', () {
      expect(sePuedeFijarNumero(15, mayorUsado: 15), isFalse);
      expect(sePuedeFijarNumero(14, mayorUsado: 15), isFalse);
    });

    test('ni cero ni negativos', () {
      expect(sePuedeFijarNumero(0, mayorUsado: 0), isFalse);
      expect(sePuedeFijarNumero(-3, mayorUsado: 0), isFalse);
    });
  });

  group('al fusionar con la nube', () {
    final viejo = _contador(16, DateTime(2026, 1, 1));
    final nuevo = _contador(6, DateTime(2026, 6, 1));

    test('gana el último cambio, aunque sea más bajo', () {
      expect(fusionarContadores(viejo, nuevo)?.nextNumber, 6);
      expect(fusionarContadores(nuevo, viejo)?.nextNumber, 6);
    });

    test('un contador sin fijar no pisa a uno fijado', () {
      expect(fusionarContadores(null, viejo), viejo);
      expect(fusionarContadores(viejo, null), viejo);
      expect(fusionarContadores(null, null), isNull);
    });
  });

  group('el mensaje de por qué no vale', () {
    test('cuando el número está cogido, dice de quién es', () {
      expect(
        mensajeNumeroNoValido(
          serie: 'F',
          year: 2026,
          numero: 27,
          mayorUsado: 30,
          ocupado: true,
        ),
        'El número 27 ya es de la factura F-2026-0027.',
      );
    });

    test('cuando está libre pero hay posteriores, lo explica', () {
      expect(
        mensajeNumeroNoValido(
          serie: 'F',
          year: 2026,
          numero: 27,
          mayorUsado: 30,
          ocupado: false,
        ),
        'No puedes usar el 27 porque ya existe la F-2026-0030: la numeración '
        'no puede retroceder. Elige uno mayor que 30.',
      );
    });
  });

  group('cerrar el hueco de una factura borrada', () {
    test('solo bajan las posteriores, y una sola posición', () {
      expect(
        renumeracionParaCerrarHueco(
          numerosPorFactura: {'a': 1, 'b': 2, 'c': 4, 'd': 5},
          numeroBorrado: 3,
        ),
        {'c': 3, 'd': 4},
      );
    });

    test('si el hueco es el último, no hay nada que mover', () {
      expect(
        renumeracionParaCerrarHueco(
          numerosPorFactura: {'a': 1, 'b': 2},
          numeroBorrado: 3,
        ),
        isEmpty,
      );
    });
  });

  test('la serie sale del tipo de factura', () {
    expect(serieDeFactura(InvoiceType.normal), 'F');
    expect(serieDeFactura(InvoiceType.rectifying), 'R');
    expect(
      numeroVisualFactura(serie: 'F', year: 2026, numero: 16),
      'F-2026-0016',
    );
  });
}
