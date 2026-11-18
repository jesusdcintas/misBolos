import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/estado_tutorial.dart';
import 'client_provider.dart';
import 'gig_provider.dart';
import 'invoice_provider.dart';
import 'settings_provider.dart';
import 'sync_provider.dart';

/// Qué tours se han visto en este dispositivo.
final tutorialProvider = AsyncNotifierProvider<TutorialNotifier, DatosTutorial>(
  TutorialNotifier.new,
);

class TutorialNotifier extends AsyncNotifier<DatosTutorial> {
  EstadoTutorial? _estado;

  @override
  Future<DatosTutorial> build() async {
    final estado = await EstadoTutorial.abrir();
    _estado = estado;
    return estado.datos;
  }

  Future<void> _conEstado(Future<void> Function(EstadoTutorial) accion) async {
    final estado = _estado ?? await EstadoTutorial.abrir();
    _estado = estado;
    await accion(estado);
    state = AsyncData(estado.datos);
  }

  /// Apunta que [tour] ya se ha visto.
  Future<void> marcarVisto(Tour tour) =>
      _conEstado((estado) => estado.marcarVisto(tour));

  /// Guarda si esta instalación es de alguien que ya usaba la app.
  Future<void> aplicarDecision(DecisionTutorial decision) =>
      _conEstado((estado) => estado.aplicarDecision(decision));

  /// Vuelve a dejar los tours y la tarjeta como el primer día.
  Future<void> repetirTutorial() =>
      _conEstado((estado) => estado.repetirTutorial());

  /// Quita la guía de inicio.
  Future<void> ocultarTarjeta() =>
      _conEstado((estado) => estado.ocultarTarjeta());

  /// El usuario se salta un paso de la guía.
  Future<void> saltarPaso(PasoGuia paso) =>
      _conEstado((estado) => estado.saltarPaso(paso));

  /// Ha contestado a la pregunta del número de factura.
  Future<void> marcarNumeracionRevisada() =>
      _conEstado((estado) => estado.marcarNumeracionRevisada());

  /// Ha compartido o enviado una factura.
  Future<void> marcarFacturaCompartida() =>
      _conEstado((estado) => estado.marcarFacturaCompartida());

  /// Encarga el tour de la pantalla a la que se manda al usuario.
  Future<void> encargarTour(Tour tour) =>
      _conEstado((estado) => estado.encargarTour(tour));

  /// Olvida el encargo, se haya usado o no.
  Future<void> olvidarEncargo() =>
      _conEstado((estado) => estado.olvidarEncargo());
}

/// Si quien abre la app ya la usaba, con los datos que hay ahora mismo.
///
/// Con sesión se espera a que haya terminado una descarga de la nube en este
/// dispositivo: hasta entonces una cuenta llena parece vacía.
final decisionTutorialProvider = Provider<DecisionTutorial>((ref) {
  final datos = ref.watch(tutorialProvider).valueOrNull;
  if (datos == null) return DecisionTutorial.esperar;

  final settings = ref.watch(settingsProvider).valueOrNull;
  final clientes = ref.watch(clientsProvider).valueOrNull;
  final bolos = ref.watch(gigsProvider).valueOrNull;
  final facturas = ref.watch(invoicesProvider).valueOrNull;

  return decidirInicioTutorial(
    yaDecidido: datos.decidido,
    conSesion: ref.watch(isCloudAuthenticatedProvider),
    ultimaDescargaNube: settings?.lastCloudSyncAt,
    datosCargados:
        settings != null &&
        clientes != null &&
        bolos != null &&
        facturas != null,
    tieneDatos:
        (clientes?.isNotEmpty ?? false) ||
        (bolos?.isNotEmpty ?? false) ||
        (facturas?.isNotEmpty ?? false),
  );
});
