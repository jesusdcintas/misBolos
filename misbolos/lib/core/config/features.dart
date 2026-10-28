/// Flags de funcionalidad de la app.
///
/// La IA (chat del asistente y redacción con IA) está aparcada: el código se
/// mantiene, pero no se muestra. Para reactivarla en desarrollo:
///   flutter run --dart-define=IA_HABILITADA=true
const bool kIaHabilitada = bool.fromEnvironment(
  'IA_HABILITADA',
  defaultValue: false,
);

/// Indica si [location] pertenece a la IA y debe bloquearse con la IA apagada.
bool esRutaDeIa(String location) => location.startsWith('/assistant');
