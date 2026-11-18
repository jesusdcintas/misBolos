import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/estado_raiz_drive.dart';

void main() {
  group('la carpeta de trabajo de Drive', () {
    test('sin elegir, no hay nada que usar', () {
      final revision = revisarRaizDrive(
        folderId: null,
        existe: false,
        enPapelera: false,
      );

      expect(revision.estado, EstadoRaizDrive.sinElegir);
      expect(revision.sePuedeUsar, isFalse);
      expect(revision.mensaje, contains('Todavía no has elegido'));
    });

    test('un id en blanco cuenta como sin elegir', () {
      expect(
        revisarRaizDrive(
          folderId: '   ',
          existe: true,
          enPapelera: false,
        ).estado,
        EstadoRaizDrive.sinElegir,
      );
    });

    test('viva y fuera de la papelera, se puede usar', () {
      final revision = revisarRaizDrive(
        folderId: 'carpeta-1',
        existe: true,
        enPapelera: false,
      );

      expect(revision.estado, EstadoRaizDrive.disponible);
      expect(revision.sePuedeUsar, isTrue);
      expect(revision.mensaje, isEmpty);
    });

    test('en la papelera no se puede usar, aunque exista', () {
      // Drive deja crear carpetas dentro de la papelera: por eso hay que
      // mirarlo antes y no fiarse de que la llamada funcione.
      final revision = revisarRaizDrive(
        folderId: 'carpeta-1',
        existe: true,
        enPapelera: true,
      );

      expect(revision.estado, EstadoRaizDrive.enPapelera);
      expect(revision.sePuedeUsar, isFalse);
      expect(revision.mensaje, contains('se ha borrado'));
    });

    test('si ya no existe, tampoco', () {
      final revision = revisarRaizDrive(
        folderId: 'carpeta-1',
        existe: false,
        enPapelera: false,
      );

      expect(revision.estado, EstadoRaizDrive.noExiste);
      expect(revision.sePuedeUsar, isFalse);
    });

    test('la excepción lleva el motivo que se le enseña al usuario', () {
      final error = RaizDriveNoDisponible(
        revisarRaizDrive(folderId: 'x', existe: true, enPapelera: true),
      );

      expect(error.mensaje, contains('papelera'));
    });
  });

  group('documentos cuyo PDF ya no está en Drive', () {
    test('se resuben los que tienen un fichero muerto', () {
      final perdidos = documentosConFicheroPerdido(
        idDrivePorDocumento: {
          'invoice:1': 'fichero-vivo',
          'invoice:2': 'fichero-muerto',
          'expense:7': 'fichero-papelera',
        },
        vivoPorFichero: {
          'fichero-vivo': true,
          'fichero-muerto': false,
          'fichero-papelera': false,
        },
      );

      expect(perdidos, {'invoice:2', 'expense:7'});
    });

    test('un documento sin fichero guardado no cuenta aquí', () {
      final perdidos = documentosConFicheroPerdido(
        idDrivePorDocumento: {'invoice:1': null, 'invoice:2': '  '},
        vivoPorFichero: const {},
      );

      expect(perdidos, isEmpty);
    });

    test('si no se pudo comprobar, no se resube', () {
      // Ante la duda, mejor no subir que acabar con dos copias del PDF.
      final perdidos = documentosConFicheroPerdido(
        idDrivePorDocumento: {'invoice:1': 'sin-respuesta'},
        vivoPorFichero: const {},
      );

      expect(perdidos, isEmpty);
    });

    test('sin documentos no hay nada que hacer', () {
      expect(
        documentosConFicheroPerdido(
          idDrivePorDocumento: const {},
          vivoPorFichero: const {},
        ),
        isEmpty,
      );
    });
  });
}
