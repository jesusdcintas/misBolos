import 'package:flutter/foundation.dart';

import '../../models/app_settings.dart';

/// Lo que conviene tener hecho para poder facturar.
enum PasoInicial { datosFiscales, google, cliente, bolo, factura }

extension PasoInicialTexto on PasoInicial {
  String get titulo => switch (this) {
    PasoInicial.datosFiscales => 'Completa tus datos fiscales',
    PasoInicial.google => 'Conecta Google (opcional)',
    PasoInicial.cliente => 'Crea tu primer cliente',
    PasoInicial.bolo => 'Añade tu primer bolo',
    PasoInicial.factura => 'Emite tu primera factura',
  };

  /// A dónde lleva al tocarlo.
  String get ruta => switch (this) {
    // Los datos de facturación y la cuenta de Google viven en Perfil.
    PasoInicial.datosFiscales => '/profile',
    PasoInicial.google => '/profile',
    PasoInicial.cliente => '/client/new',
    PasoInicial.bolo => '/gig/new',
    // Una factura nace de un bolo, así que se empieza por la agenda.
    PasoInicial.factura => '/calendar',
  };
}

@immutable
class EstadoPasoInicial {
  final PasoInicial paso;
  final bool completado;

  const EstadoPasoInicial(this.paso, {required this.completado});
}

/// Si los datos de facturación están lo bastante completos para emitir.
///
/// Nombre, NIF y dirección son los que el PDF necesita sí o sí.
bool datosFiscalesCompletos(AppSettings? settings) {
  if (settings == null) return false;
  return settings.emisorNombre.trim().isNotEmpty &&
      settings.emisorNIF.trim().isNotEmpty &&
      settings.emisorDireccion.trim().isNotEmpty;
}

/// Qué pasos lleva hechos quien empieza, con los datos que ya hay.
List<EstadoPasoInicial> primerosPasos({
  required AppSettings? settings,
  required bool googleConectado,
  required bool hayClientes,
  required bool hayBolos,
  required bool hayFacturas,
}) => [
  EstadoPasoInicial(
    PasoInicial.datosFiscales,
    completado: datosFiscalesCompletos(settings),
  ),
  EstadoPasoInicial(PasoInicial.google, completado: googleConectado),
  EstadoPasoInicial(PasoInicial.cliente, completado: hayClientes),
  EstadoPasoInicial(PasoInicial.bolo, completado: hayBolos),
  EstadoPasoInicial(PasoInicial.factura, completado: hayFacturas),
];

/// Cuántos pasos están hechos.
int pasosCompletados(List<EstadoPasoInicial> pasos) =>
    pasos.where((p) => p.completado).length;

/// Si ya no hay nada que hacer y la tarjeta sobra.
bool primerosPasosTerminados(List<EstadoPasoInicial> pasos) =>
    pasos.every((p) => p.completado);
