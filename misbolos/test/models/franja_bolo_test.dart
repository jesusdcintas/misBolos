import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/models/franja_bolo.dart';
import 'package:misbolos/models/gig.dart';

void main() {
  group('FranjaBolo', () {
    test('los valores guardados son los acordados', () {
      expect(FranjaBolo.tarde.dbValue, 'tarde');
      expect(FranjaBolo.noche.dbValue, 'noche');
      expect(FranjaBolo.diaCompleto.dbValue, 'dia_completo');
    });

    test('las etiquetas visibles llevan tilde donde toca', () {
      expect(FranjaBolo.tarde.label, 'Tarde');
      expect(FranjaBolo.noche.label, 'Noche');
      expect(FranjaBolo.diaCompleto.label, 'Todo el día');
    });

    test('solo tarde y noche se etiquetan en las listas', () {
      expect(FranjaBolo.tarde.seEtiqueta, isTrue);
      expect(FranjaBolo.noche.seEtiqueta, isTrue);
      expect(FranjaBolo.diaCompleto.seEtiqueta, isFalse);
    });

    test('qué franjas ocupa cada una', () {
      expect(FranjaBolo.tarde.ocupaTarde, isTrue);
      expect(FranjaBolo.tarde.ocupaNoche, isFalse);
      expect(FranjaBolo.noche.ocupaTarde, isFalse);
      expect(FranjaBolo.noche.ocupaNoche, isTrue);
      expect(FranjaBolo.diaCompleto.ocupaTarde, isTrue);
      expect(FranjaBolo.diaCompleto.ocupaNoche, isTrue);
    });
  });

  group('franjaFromDb', () {
    test('lee los tres valores', () {
      expect(franjaFromDb('tarde'), FranjaBolo.tarde);
      expect(franjaFromDb('noche'), FranjaBolo.noche);
      expect(franjaFromDb('dia_completo'), FranjaBolo.diaCompleto);
    });

    test('un null se conserva como null, no se convierte', () {
      expect(franjaFromDb(null), isNull);
    });

    test('un valor desconocido no se inventa una franja', () {
      expect(franjaFromDb('madrugada'), isNull);
      expect(franjaFromDb(''), isNull);
    });
  });

  group('franjaEfectiva', () {
    test('sin franja guardada se asume todo el día', () {
      expect(franjaEfectiva(null), FranjaBolo.diaCompleto);
    });

    test('con franja guardada la respeta', () {
      expect(franjaEfectiva(FranjaBolo.tarde), FranjaBolo.tarde);
      expect(franjaEfectiva(FranjaBolo.noche), FranjaBolo.noche);
    });
  });

  group('Gig con franja', () {
    Gig gigDe(FranjaBolo? franja) =>
        Gig(fecha: DateTime(2026, 11, 14), clientId: 'c1', franja: franja);

    test('un bolo nuevo sin franja la deja en null', () {
      expect(Gig(fecha: DateTime(2026, 11, 14), clientId: 'c1').franja, isNull);
    });

    test('la franja sobrevive a la ida y vuelta toMap -> fromMap', () {
      for (final franja in FranjaBolo.values) {
        final recuperado = Gig.fromMap(gigDe(franja).toMap());
        expect(recuperado.franja, franja);
      }
    });

    test('un null sobrevive a la ida y vuelta como null', () {
      expect(Gig.fromMap(gigDe(null).toMap()).franja, isNull);
    });

    test('toMap guarda el valor acordado', () {
      expect(gigDe(FranjaBolo.noche).toMap()['franja'], 'noche');
      expect(gigDe(null).toMap()['franja'], isNull);
    });

    test('un bolo antiguo sin la clave franja se lee como null', () {
      final map = gigDe(FranjaBolo.tarde).toMap()..remove('franja');
      expect(Gig.fromMap(map).franja, isNull);
    });

    test('copyWith cambia la franja', () {
      expect(
        gigDe(FranjaBolo.tarde).copyWith(franja: FranjaBolo.noche).franja,
        FranjaBolo.noche,
      );
    });

    test('copyWith sin franja conserva la que había', () {
      expect(gigDe(FranjaBolo.tarde).copyWith(cachet: 300).franja,
          FranjaBolo.tarde);
    });
  });
}
