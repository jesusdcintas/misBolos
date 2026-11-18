import 'package:flutter/foundation.dart';

/// En qué estado está la carpeta de trabajo de Drive.
enum EstadoRaizDrive {
  /// Existe y se puede usar.
  disponible,

  /// El usuario la ha borrado: sigue existiendo, pero en la papelera.
  ///
  /// Drive deja crear cosas dentro, así que sin comprobarlo la app creaba
  /// las carpetas ahí y decía que todo estaba listo.
  enPapelera,

  /// Ya no existe, o la cuenta ya no puede verla.
  noExiste,

  /// Todavía no se ha elegido ninguna.
  sinElegir,
}

/// Lo que hay que hacer con la raíz antes de crear o subir nada.
@immutable
class RevisionRaizDrive {
  final EstadoRaizDrive estado;

  const RevisionRaizDrive(this.estado);

  /// Si se puede seguir creando carpetas y subiendo documentos.
  bool get sePuedeUsar => estado == EstadoRaizDrive.disponible;

  /// Qué contarle al usuario cuando no se puede usar.
  String get mensaje => switch (estado) {
    EstadoRaizDrive.disponible => '',
    EstadoRaizDrive.enPapelera =>
      'La carpeta de MisBolos de tu Drive se ha borrado. Está en la papelera, '
          'así que lo que se guarde ahí no lo verás.',
    EstadoRaizDrive.noExiste =>
      'La carpeta de MisBolos de tu Drive se ha borrado.',
    EstadoRaizDrive.sinElegir =>
      'Todavía no has elegido una carpeta de trabajo en Drive.',
  };
}

/// Decide el estado a partir de lo que Drive cuenta de la carpeta.
///
/// [existe] a false cubre tanto que Drive devuelva 404 como que la cuenta ya
/// no tenga acceso: para el usuario es lo mismo.
RevisionRaizDrive revisarRaizDrive({
  required String? folderId,
  required bool existe,
  required bool enPapelera,
}) {
  final id = folderId?.trim();
  if (id == null || id.isEmpty) {
    return const RevisionRaizDrive(EstadoRaizDrive.sinElegir);
  }
  if (!existe) return const RevisionRaizDrive(EstadoRaizDrive.noExiste);
  if (enPapelera) return const RevisionRaizDrive(EstadoRaizDrive.enPapelera);
  return const RevisionRaizDrive(EstadoRaizDrive.disponible);
}

/// La carpeta de trabajo no se puede usar: no hay que crear nada dentro.
class RaizDriveNoDisponible implements Exception {
  final RevisionRaizDrive revision;

  const RaizDriveNoDisponible(this.revision);

  String get mensaje => revision.mensaje;

  @override
  String toString() => mensaje;
}

/// De los documentos que creen tener su PDF en Drive, cuáles ya no lo tienen.
///
/// [idDrivePorDocumento] va del id del documento (factura, gasto o inversión)
/// al id del fichero que tiene guardado. [vivoPorFichero] dice, de cada
/// fichero consultado, si sigue existiendo y fuera de la papelera.
///
/// Un fichero que no se pudo consultar no cuenta como perdido: ante la duda
/// es mejor no subir nada que acabar con dos copias del mismo PDF.
Set<String> documentosConFicheroPerdido({
  required Map<String, String?> idDrivePorDocumento,
  required Map<String, bool> vivoPorFichero,
}) {
  final perdidos = <String>{};
  for (final entrada in idDrivePorDocumento.entries) {
    final idFichero = entrada.value?.trim();
    if (idFichero == null || idFichero.isEmpty) continue;
    if (vivoPorFichero[idFichero] == false) perdidos.add(entrada.key);
  }
  return perdidos;
}
