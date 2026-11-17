import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/arbol_drive.dart';

List<String> _nombres(NodoCarpeta nodo) => [
  nodo.nombre,
  for (final hijo in nodo.hijos) ..._nombres(hijo),
];

CarpetaDrive _carpeta(String nombre, [String id = 'id']) =>
    CarpetaDrive(id: id, nombre: nombre);

void main() {
  group('el árbol de un año', () {
    final arbol = arbolDeAno(2026);

    test('son 41 carpetas: 1 + 4 trimestres + 12 meses + 24 de documentos', () {
      expect(cuentaCarpetas(arbol), 41);
    });

    test('cuelga de la carpeta del año', () {
      expect(arbol.nombre, 'Contabilidad 2026');
      expect(arbol.hijos.map((t) => t.nombre), [
        '1 TRIMESTRE',
        '2 TRIMESTRE',
        '3 TRIMESTRE',
        '4 TRIMESTRE',
      ]);
    });

    test('cada trimestre lleva sus tres meses en orden', () {
      expect(arbol.hijos.first.hijos.map((m) => m.nombre), [
        'ENERO',
        'FEBRERO',
        'MARZO',
      ]);
      expect(arbol.hijos.last.hijos.map((m) => m.nombre), [
        'OCTUBRE',
        'NOVIEMBRE',
        'DICIEMBRE',
      ]);
    });

    test('cada mes lleva solo las dos carpetas de documentos', () {
      for (final trimestre in arbol.hijos) {
        for (final mes in trimestre.hijos) {
          expect(mes.hijos.map((c) => c.nombre), [
            'FACTURAS',
            'GASTOS E INVERSIONES',
          ], reason: mes.nombre);
        }
      }
    });

    test('ya no se crean GASTOS, INVERSIONES ni MODELOS', () {
      final nombres = _nombres(arbol);
      for (final retirada in [...carpetasRetiradas, 'MODELOS']) {
        expect(nombres, isNot(contains(retirada)), reason: retirada);
      }
      // Pero «GASTOS E INVERSIONES» sí está: no confundir una con otra.
      expect(nombres, contains(carpetaGastosEInversiones));
    });
  });

  group('la carpeta de gastos e inversiones de un mes', () {
    test('si no hay ninguna, se crea', () {
      final decision = decidirCarpetaGastos([_carpeta('FACTURAS')]);

      expect(decision.accion, AccionCarpetaGastos.crear);
      expect(decision.id, isNull);
    });

    test('si ya está con el nombre bueno, se usa tal cual', () {
      final decision = decidirCarpetaGastos([
        _carpeta('FACTURAS', 'f'),
        _carpeta('GASTOS E INVERSIONES', 'g'),
      ]);

      expect(decision.accion, AccionCarpetaGastos.usar);
      expect(decision.id, 'g');
    });

    test('si está la antigua, se renombra en su sitio', () {
      final decision = decidirCarpetaGastos([
        _carpeta('FACTURAS', 'f'),
        _carpeta('Gastos e Inversiones', 'g'),
      ]);

      expect(decision.accion, AccionCarpetaGastos.renombrar);
      // La misma carpeta: ni se crea otra ni se mueven los PDF.
      expect(decision.id, 'g');
    });

    test('cualquier variante de mayúsculas cuenta como la antigua', () {
      for (final nombre in [
        'gastos e inversiones',
        'Gastos E Inversiones',
        ' GASTOS E INVERSIONES ',
      ]) {
        final decision = decidirCarpetaGastos([_carpeta(nombre, 'g')]);
        expect(decision.accion, AccionCarpetaGastos.renombrar, reason: nombre);
      }
    });

    test('si conviven las dos, se usa la de mayúsculas y no se fusionan', () {
      final decision = decidirCarpetaGastos([
        _carpeta('Gastos e Inversiones', 'vieja'),
        _carpeta('GASTOS E INVERSIONES', 'nueva'),
      ]);

      expect(decision.accion, AccionCarpetaGastos.duplicadas);
      expect(decision.id, 'nueva');
    });

    test('una carpeta parecida no se toca', () {
      final decision = decidirCarpetaGastos([
        _carpeta('GASTOS'),
        _carpeta('INVERSIONES'),
        _carpeta('Gastos e Inversiones 2024'),
      ]);

      expect(decision.accion, AccionCarpetaGastos.crear);
    });
  });

  group('la ruta de un adjunto de gasto', () {
    test('usa los mismos nombres que el árbol', () {
      final fecha = DateTime(2026, 5, 14);

      expect(getYearFolderName(fecha), 'Contabilidad 2026');
      expect(getQuarterName(fecha), '2 TRIMESTRE');
      expect(getMonthName(fecha), 'MAYO');
    });
  });
}
