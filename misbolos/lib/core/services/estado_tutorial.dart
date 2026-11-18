import 'package:shared_preferences/shared_preferences.dart';

import 'guia_inicio.dart';

export 'guia_inicio.dart';

/// Lo que hay que hacer con la primera decisión del tutorial.
enum DecisionTutorial {
  /// Todavía no se sabe: no se enseña nada y se vuelve a mirar más tarde.
  esperar,

  /// Ya venía usando la app: no debe ver el tutorial de golpe.
  usuarioExistente,

  /// Empieza de cero: le toca el tutorial.
  usuarioNuevo,
}

/// Decide si quien abre la app ya la usaba, y por tanto no debe ver el
/// tutorial, o si empieza de cero.
///
/// La clave está en no decidir antes de tiempo: una cuenta con datos en la
/// nube parece vacía hasta que termina la primera descarga en este
/// dispositivo. Mientras no haya terminado, se espera; si falla, se vuelve a
/// mirar en la siguiente apertura. Sin sesión (modo invitado) no hay nube que
/// esperar y basta con lo que haya en el dispositivo.
DecisionTutorial decidirInicioTutorial({
  required bool yaDecidido,
  required bool conSesion,
  required DateTime? ultimaDescargaNube,
  required bool datosCargados,
  required bool tieneDatos,
}) {
  if (yaDecidido) return DecisionTutorial.esperar;
  if (!datosCargados) return DecisionTutorial.esperar;
  if (conSesion && ultimaDescargaNube == null) return DecisionTutorial.esperar;
  return tieneDatos
      ? DecisionTutorial.usuarioExistente
      : DecisionTutorial.usuarioNuevo;
}

/// Lo que se sabe del tutorial en un momento dado.
class DatosTutorial {
  /// Si ya se decidió si esta instalación es de alguien que venía usando la
  /// app. Hasta entonces no se enseña ni un tour ni la tarjeta.
  final bool decidido;

  /// Los tours que ya se han visto.
  final Set<Tour> vistos;

  /// Si la guía de inicio se ha ocultado a mano.
  final bool tarjetaOculta;

  /// Pasos que el usuario ha decidido saltarse.
  final Set<PasoGuia> pasosSaltados;

  /// El usuario ya ha contestado a la pregunta del número de factura.
  final bool numeracionRevisada;

  /// El usuario ya ha compartido o enviado una factura.
  final bool facturaCompartida;

  /// El tour que la guía ha encargado al mandar al usuario a una pantalla.
  ///
  /// Caduca: si no se muestra, no debe saltar por sorpresa media hora
  /// después.
  final Tour? tourPendiente;
  final DateTime? tourPendienteDesde;

  const DatosTutorial({
    required this.decidido,
    required this.vistos,
    required this.tarjetaOculta,
    this.pasosSaltados = const {},
    this.numeracionRevisada = false,
    this.facturaCompartida = false,
    this.tourPendiente,
    this.tourPendienteDesde,
  });

  /// Cuánto aguanta un encargo de tour sin usarse.
  static const caducidadEncargo = Duration(minutes: 3);

  /// Si [tour] es el que la guía encargó y el encargo sigue fresco.
  bool encargoVigente(Tour tour, {DateTime? ahora}) {
    if (tourPendiente != tour) return false;
    final desde = tourPendienteDesde;
    if (desde == null) return false;
    return (ahora ?? DateTime.now()).difference(desde) < caducidadEncargo;
  }

  bool estaVisto(Tour tour) => vistos.contains(tour);

  /// Si [tour] debe saltar solo al entrar en su pantalla.
  bool tocaMostrar(Tour tour) => decidido && !estaVisto(tour);

  /// Si la tarjeta de primeros pasos puede pintarse.
  bool get tarjetaVisible => decidido && !tarjetaOculta;
}

/// Qué tours se han visto en este dispositivo.
///
/// Se guarda solo aquí, con SharedPreferences: es algo de esta instalación,
/// no de la cuenta, así que no viaja a la nube.
class EstadoTutorial {
  static const claveInicializado = 'tutorial_v1_inicializado';
  static const claveTarjetaOculta = 'tutorial_v1_tarjeta_oculta';

  static const claveNumeracionRevisada = 'tutorial_v1_numeracion_revisada';
  static const claveFacturaCompartida = 'tutorial_v1_factura_compartida';
  static const claveTourPendiente = 'tutorial_v1_tour_pendiente';
  static const claveTourPendienteDesde = 'tutorial_v1_tour_pendiente_desde';

  static String claveVisto(Tour tour) => 'tutorial_v1_visto_${tour.name}';

  static String claveSaltado(PasoGuia paso) =>
      'tutorial_v1_saltado_${paso.name}';

  final SharedPreferences _prefs;

  const EstadoTutorial(this._prefs);

  static Future<EstadoTutorial> abrir() async =>
      EstadoTutorial(await SharedPreferences.getInstance());

  DatosTutorial get datos {
    final nombreTour = _prefs.getString(claveTourPendiente);
    final desde = _prefs.getString(claveTourPendienteDesde);
    return DatosTutorial(
      decidido: _prefs.getBool(claveInicializado) ?? false,
      vistos: {
        for (final tour in Tour.values)
          if (_prefs.getBool(claveVisto(tour)) ?? false) tour,
      },
      tarjetaOculta: _prefs.getBool(claveTarjetaOculta) ?? false,
      pasosSaltados: {
        for (final paso in PasoGuia.values)
          if (_prefs.getBool(claveSaltado(paso)) ?? false) paso,
      },
      numeracionRevisada: _prefs.getBool(claveNumeracionRevisada) ?? false,
      facturaCompartida: _prefs.getBool(claveFacturaCompartida) ?? false,
      tourPendiente: nombreTour == null
          ? null
          : Tour.values.where((t) => t.name == nombreTour).firstOrNull,
      tourPendienteDesde: desde == null ? null : DateTime.tryParse(desde),
    );
  }

  /// Apunta que el usuario se salta [paso].
  Future<void> saltarPaso(PasoGuia paso) async {
    await _prefs.setBool(claveSaltado(paso), true);
  }

  /// Apunta que ha contestado a la pregunta del número de factura.
  Future<void> marcarNumeracionRevisada() async {
    await _prefs.setBool(claveNumeracionRevisada, true);
  }

  /// Apunta que ha compartido o enviado una factura.
  Future<void> marcarFacturaCompartida() async {
    await _prefs.setBool(claveFacturaCompartida, true);
  }

  /// Encarga un tour para la pantalla a la que se va a mandar al usuario.
  Future<void> encargarTour(Tour tour) async {
    await _prefs.setString(claveTourPendiente, tour.name);
    await _prefs.setString(
      claveTourPendienteDesde,
      DateTime.now().toIso8601String(),
    );
  }

  /// Olvida el encargo: ya se ha usado, o el usuario se fue a otra parte.
  Future<void> olvidarEncargo() async {
    await _prefs.remove(claveTourPendiente);
    await _prefs.remove(claveTourPendienteDesde);
  }

  /// Apunta que [tour] ya se ha visto, para que no vuelva a saltar solo.
  Future<void> marcarVisto(Tour tour) async {
    await _prefs.setBool(claveVisto(tour), true);
  }

  /// Aplica la decisión de [decidirInicioTutorial].
  ///
  /// Con [DecisionTutorial.esperar] no escribe nada: así, si la descarga de la
  /// nube falló, la siguiente apertura vuelve a intentarlo.
  Future<void> aplicarDecision(DecisionTutorial decision) async {
    if (decision == DecisionTutorial.esperar) return;
    if (decision == DecisionTutorial.usuarioExistente) {
      for (final tour in Tour.values) {
        await _prefs.setBool(claveVisto(tour), true);
      }
      await _prefs.setBool(claveTarjetaOculta, true);
    }
    await _prefs.setBool(claveInicializado, true);
  }

  /// Vuelve a dejar todos los tours y la tarjeta como el primer día.
  Future<void> repetirTutorial() async {
    for (final tour in Tour.values) {
      await _prefs.remove(claveVisto(tour));
    }
    for (final paso in PasoGuia.values) {
      await _prefs.remove(claveSaltado(paso));
    }
    await _prefs.remove(claveTarjetaOculta);
    await _prefs.remove(claveNumeracionRevisada);
    await _prefs.remove(claveFacturaCompartida);
    await olvidarEncargo();
    // Decidido se queda: ya se sabe de qué pie calza esta instalación y, si
    // se borrara, la decisión volvería a marcarlo todo como visto.
    await _prefs.setBool(claveInicializado, true);
  }

  /// Quita la tarjeta de primeros pasos para quien no la quiera.
  Future<void> ocultarTarjeta() async {
    await _prefs.setBool(claveTarjetaOculta, true);
  }
}
