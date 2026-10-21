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
        ExpensePdfParser.parse('''
Base imponible 1.000,00
IVA 234,56
Total: 1.234,56 €
''').total.valor,
        1234.56,
      );
      expect(
        ExpensePdfParser.parse('''
Base imponible 1000.00
IVA 234.56
Total: 1234.56 EUR
''').total.valor,
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

  // Textos sintéticos con la estructura de facturas reales, sin datos personales.
  group('ExpensePdfParser casos reales anonimizados', () {
    const nifUsuario = '00000000T';
    const nombreUsuario = 'Usuario Ejemplo';

    ExpensePdfParseResult parse(String texto) => ExpensePdfParser.parse(
      texto,
      nifUsuario: nifUsuario,
      nombreUsuario: nombreUsuario,
    );

    test('1. TOTAL al final de la línea de OBSERVACIONES', () {
      const texto = '''
Proveedor Ejemplo S.L.
C/ Ejemplo 12, 28001 Madrid
CIF: B00000000
FACTURA Nº F-2026/0153
Fecha: 17/07/2026
CLIENTE
Usuario Ejemplo
NIF: 00000000T
Concepto Importe
Alquiler de equipo 90,00
BASE IMPONIBLE 90,00
IVA 21% 18,90
OBSERVACIONES: Pago por transferencia      TOTAL: 108,90 €
''';
      final result = parse(texto);

      expect(result.total.valor, 108.90);
      expect(result.fecha.valor, DateTime(2026, 7, 17));
      expect(result.proveedor.valor, 'Proveedor Ejemplo S.L.');
    });

    test('2. TOTAL FACTURA EUROS y fecha de operación distinta', () {
      const texto = '''
Gasolinera Ejemplo, S.A.
Avda. del Ejemplo s/n
CIF A00000000
FACTURA SIMPLIFICADA
Fecha: 10/09/2026   F. Operación: 09/09/2026
Producto: Gasóleo A
Litros 60,50
BASE IMPONIBLE 82,89
IVA 21% 17,40
TOTAL FACTURA EUROS........ 100,29 €
Pago con Mastercard ****1234 100,29
''';
      final result = parse(texto);

      expect(result.total.valor, 100.29);
      expect(result.fecha.valor, DateTime(2026, 9, 10));
      expect(result.proveedor.valor, 'Gasolinera Ejemplo, S.A.');
    });

    test('3. Factura en inglés con GmbH, dirección y Total Price', () {
      const texto = '''
Thomann Ejemplo GmbH, Hans-Ejemplo-Str. 1, 96138 Burgebrach
VAT ID: DE000000000
Invoice
Usuario Ejemplo
Calle Falsa 1
28001 Madrid
NIF: 00000000T
Invoice no. 0000000
Date: 22.07.2026
Article Qty Total Price
Cable XLR 2 40,00
Total Price 667,81
Net amount 667,81
VAT 21% 140,24
Total amount: 808,05 EUR
Amount carried forward 0,00
''';
      final result = parse(texto);

      expect(result.total.valor, 808.05);
      expect(result.fecha.valor, DateTime(2026, 7, 22));
      expect(result.proveedor.valor, 'Thomann Ejemplo GmbH');
    });

    test('4. Nunca sugiere el nombre del usuario como proveedor', () {
      const conUsuarioPrimero = '''
Usuario Ejemplo
Calle Falsa 1
NIF: 00000000-T

Fecha: 01/03/2026
Total: 50,00
''';
      final result = parse(conUsuarioPrimero);

      expect(result.proveedor.valor, isNot(nombreUsuario));
      expect(result.proveedor.encontrado, isFalse);

      const conAdquiriente = '''
Estudio Ejemplo
Datos del cliente:
Usuario Ejemplo
NIF: 00000000T
''';
      expect(parse(conAdquiriente).proveedor.valor, isNot(nombreUsuario));
    });

    test('5. Dos totales distintos: total vacío', () {
      const texto = '''
Tienda Ejemplo
Total 100,00
Total 121,00
''';
      expect(parse(texto).total.encontrado, isFalse);
    });

    test('6. Solo Subtotal: total vacío', () {
      const texto = '''
Tienda Ejemplo
Subtotal 80,00
IVA 21% 16,80
''';
      expect(parse(texto).total.encontrado, isFalse);
    });

    test('7. Fechas dd.mm.yyyy y dd-mm-yyyy', () {
      expect(parse('Date: 22.07.2026').fecha.valor, DateTime(2026, 7, 22));
      expect(parse('Fecha: 17-07-2026').fecha.valor, DateTime(2026, 7, 17));
    });

    test('etiqueta de total sola con el importe en la línea siguiente', () {
      const texto = '''
Tienda Ejemplo
Base imponible 30,00
IVA 15,30
TOTAL:
45,30 €
''';
      expect(parse(texto).total.valor, 45.30);
    });

    test('valida TOTAL FACTURA EUROS con suma base + IVA', () {
      const texto = '''
Proveedor Demo S.L.
Base imponible 82,88 €
IVA 21% 17,41 €
TOTAL FACTURA EUROS.... 100,29 €
''';

      final result = parse(texto);

      expect(result.total.encontrado, isTrue);
      expect(result.total.valor, 100.29);
    });

    test('valida Total amount con suma de dos importes', () {
      const texto = '''
Vendor Demo GmbH
Net amount 667,81
VAT 21% 140,24
Total amount: 808,05 EUR
''';

      final result = parse(texto);

      expect(result.total.encontrado, isTrue);
      expect(result.total.valor, 808.05);
    });

    test('valida TOTAL en tabla con base e IVA', () {
      const texto = '''
Concepto Importe
Base imponible 90,00
IVA 21% 18,90
TOTAL: 108,90
''';

      final result = parse(texto);

      expect(result.total.encontrado, isTrue);
      expect(result.total.valor, 108.90);
    });

    test('solo base imponible sin etiqueta de total deja total vacío', () {
      const texto = '''
Proveedor Demo
Base imponible 82,88 €
''';

      final result = parse(texto);

      expect(result.total.encontrado, isFalse);
      expect(result.total.valor, isNull);
    });

    test('TOTAL igual a base sin IVA que complete deja total vacío', () {
      const texto = '''
Proveedor Demo
Base imponible 82,88 €
TOTAL 82,88 €
''';

      final result = parse(texto);

      expect(result.total.encontrado, isFalse);
      expect(result.total.valor, isNull);
    });

    test('dos etiquetas total: si ambas cumplen valores distintos, total vacío', () {
      const texto = '''
Proveedor Demo
Base imponible 90,00
IVA 21% 18,90
Retención 10,00
TOTAL: 108,90
Total amount: 100,00 EUR
''';

      final result = parse(texto);

      expect(result.total.encontrado, isFalse);
      expect(result.total.valor, isNull);
    });

    test('dos etiquetas total: si solo una cumple suma, se sugiere esa', () {
      const texto = '''
Proveedor Demo
Base imponible 90,00
IVA 21% 18,90
TOTAL: 108,90
Total amount: 120,00 EUR
''';

      final result = parse(texto);

      expect(result.total.encontrado, isTrue);
      expect(result.total.valor, 108.90);
    });
  });
}
