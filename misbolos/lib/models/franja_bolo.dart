/// Franja del día que ocupa un bolo.
enum FranjaBolo { tarde, noche, diaCompleto }

extension FranjaBoloExtension on FranjaBolo {
  /// Valor que se guarda en la base de datos.
  String get dbValue => switch (this) {
    FranjaBolo.tarde => 'tarde',
    FranjaBolo.noche => 'noche',
    FranjaBolo.diaCompleto => 'dia_completo',
  };

  /// Texto visible.
  String get label => switch (this) {
    FranjaBolo.tarde => 'Tarde',
    FranjaBolo.noche => 'Noche',
    FranjaBolo.diaCompleto => 'Todo el día',
  };

  /// Si se muestra como etiqueta en las listas. «Todo el día» no se marca.
  bool get seEtiqueta => this != FranjaBolo.diaCompleto;

  bool get ocupaTarde => this != FranjaBolo.noche;

  bool get ocupaNoche => this != FranjaBolo.tarde;
}

/// Lee la franja guardada.
///
/// Un null se devuelve como null, sin convertirlo: son los bolos creados antes
/// de que existiera la franja. Quien necesite un valor concreto usa
/// [franjaEfectiva]. Un valor desconocido también devuelve null, para no
/// inventarse una franja que no se guardó.
FranjaBolo? franjaFromDb(String? value) {
  if (value == null) return null;
  for (final franja in FranjaBolo.values) {
    if (franja.dbValue == value) return franja;
  }
  return null;
}

/// Franja con la que se trabaja en la ocupación y en la interfaz.
///
/// Sin franja guardada se asume «Todo el día»: así nunca se ofrece un hueco
/// que quizá no está libre.
FranjaBolo franjaEfectiva(FranjaBolo? franja) => franja ?? FranjaBolo.diaCompleto;
