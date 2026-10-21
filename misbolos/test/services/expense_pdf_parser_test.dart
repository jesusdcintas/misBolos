import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/services/expense_pdf_parser.dart';

void main() {
  group('ExpensePdfParser', () {
    test('sugiere fecha, total y proveedor en una factura típica', () {
      const texto = '''
Sonido Pro S.L.
CIF: B12345678
Calle Mayor 1, Madrid
Factura nº 2026-045
Fecha de factura: 14/03/2026
Fecha de vencimiento: 14/04/2026
Subtotal 1.000,00 €
Base imponible 1.000,00 €
IVA 21% 210,00 €
Total 1.210,00 €
''';
      final result = ExpensePdfParser.parse(texto);

      expect(result.fecha.encontrado, isTrue);
      expect(result.fecha.valor, DateTime(2026, 3, 14));
      expect(result.total.encontrado, isTrue);
      expect(result.total.valor, 1210.00);
      expect(result.proveedor.encontrado, isTrue);
      expect(result.proveedor.valor, 'Sonido Pro S.L.');
      expect(result.algunoEncontrado, isTrue);
    });

    test('con varios totales distintos no sugiere ninguno', () {
      const texto = '''
Tienda Ejemplo
Fecha: 01/02/2026
Total 100,00
Importe total 121,00
''';
      final result = ExpensePdfParser.parse(texto);

      expect(result.total.encontrado, isFalse);
      expect(result.total.valor, isNull);
    });

    test('con varias fechas sin contexto deja la fecha vacía', () {
      const texto = '''
Tienda Ejemplo
01/02/2026
15/02/2026
Total 50,00
''';
      final result = ExpensePdfParser.parse(texto);

      expect(result.fecha.encontrado, isFalse);
      expect(result.fecha.valor, isNull);
    });

    test('acepta fechas con guion y con punto', () {
      expect(
        ExpensePdfParser.parse('Fecha: 05-06-2026').fecha.valor,
        DateTime(2026, 6, 5),
      );
      expect(
        ExpensePdfParser.parse('Fecha: 05.06.2026').fecha.valor,
        DateTime(2026, 6, 5),
      );
    });

    test('interpreta importes con coma decimal y con punto decimal', () {
      expect(
        ExpensePdfParser.parse('Total: 1.234,56 €').total.valor,
        1234.56,
      );
      expect(
        ExpensePdfParser.parse('Total: 1234.56 EUR').total.valor,
        1234.56,
      );
      expect(ExpensePdfParser.parseImporte('1.234,56'), 1234.56);
      expect(ExpensePdfParser.parseImporte('1234,56'), 1234.56);
      expect(ExpensePdfParser.parseImporte('1,234.56'), 1234.56);
      expect(ExpensePdfParser.parseImporte('1234.56'), 1234.56);
      expect(ExpensePdfParser.parseImporte('1.234'), 1234);
    });

    test('texto vacío: no sugiere nada', () {
      final result = ExpensePdfParser.parse('');

      expect(result.algunoEncontrado, isFalse);
    });

    test('no toma como proveedor una cabecera genérica', () {
      const texto = '''
FACTURA
Fecha: 10/01/2026
Total 20,00
''';
      final result = ExpensePdfParser.parse(texto);

      expect(result.proveedor.encontrado, isFalse);
    });
  });
}
