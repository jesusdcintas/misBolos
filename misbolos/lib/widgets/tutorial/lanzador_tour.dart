import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../core/services/estado_tutorial.dart';
import '../../providers/tutorial_provider.dart';
import 'bocadillo_tour.dart';
import 'tour.dart';

/// Solo puede haber un tour en pantalla: ninguno salta encima de otro.
bool _hayTourAbierto = false;

/// Enseña [pasos] como un tour sobre la pantalla actual.
///
/// Los pasos cuyo elemento no esté en pantalla (una lista vacía, un botón que
/// no se pinta) se omiten sin fallar. Devuelve si llegó a mostrarse, para que
/// quien lo pida pueda reintentarlo.
///
/// Con [guardarVisto] a false no se toca nada de lo guardado: es lo que hace
/// falta para el botón de ayuda, que repite el tour de una pantalla sin
/// cambiar el estado de los demás.
Future<bool> mostrarTour(
  BuildContext context,
  WidgetRef ref, {
  required Tour tour,
  required List<PasoTour> pasos,
  bool guardarVisto = true,
}) async {
  if (_hayTourAbierto) return false;

  // Con un diálogo o una hoja por encima, la pantalla no es la que manda.
  final ruta = ModalRoute.of(context);
  if (ruta != null && !ruta.isCurrent) return false;

  final visibles = pasos
      .where((paso) => paso.clave.currentContext != null)
      .toList();
  if (visibles.isEmpty) return false;

  final scheme = Theme.of(context).colorScheme;
  final alto = MediaQuery.of(context).size.height;
  final sinAnimaciones = MediaQuery.of(context).disableAnimations;
  final duracion = sinAnimaciones
      ? Duration.zero
      : const Duration(milliseconds: 320);

  _hayTourAbierto = true;
  var cerrado = false;
  void terminar() {
    if (cerrado) return;
    cerrado = true;
    _hayTourAbierto = false;
    if (guardarVisto) {
      unawaited(ref.read(tutorialProvider.notifier).marcarVisto(tour));
    }
  }

  // Sin la referencia no se puede cerrar el tour desde el velo.
  late final TutorialCoachMark tutorial;
  tutorial = TutorialCoachMark(
    targets: [
      for (final (indice, paso) in visibles.indexed)
        TargetFocus(
          identify: '${tour.name}-$indice',
          keyTarget: paso.clave,
          shape: paso.redondo ? ShapeLightFocus.Circle : ShapeLightFocus.RRect,
          radius: 14,
          enableTargetTab: false,
          // Tocar fuera del bocadillo cierra el tour, siempre.
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: _alineacion(paso, alto),
              builder: (context, controlador) => BocadilloTour(
                numero: indice + 1,
                total: visibles.length,
                texto: paso.texto,
                alSiguiente: controlador.next,
                alSaltar: controlador.skip,
                alAnterior: indice == 0 ? null : controlador.previous,
              ),
            ),
          ],
        ),
    ],
    colorShadow: scheme.scrim,
    opacityShadow: 0.72,
    paddingFocus: 8,
    // Red de seguridad: el bocadillo lleva su «Saltar», pero si por lo que
    // sea no se ve, el del paquete sigue ahí y tocar fuera cierra el tour.
    // Sin esto, un objetivo fuera de pantalla dejaba la app bloqueada.
    hideSkip: false,
    textSkip: 'Saltar',
    onClickOverlay: (_) {
      // Cerrar a mano además de pedir el skip: si no, el tour se daba por
      // abierto para siempre y el siguiente ya no salía.
      terminar();
      tutorial.skip();
    },
    // Antes de cada paso, traer el elemento a la vista: en Perfil y en
    // Ajustes muchos quedan por debajo del pliegue.
    beforeFocus: (objetivo) async {
      final destino = objetivo.keyTarget?.currentContext;
      if (destino == null) return;
      await Scrollable.ensureVisible(
        destino,
        duration: duracion,
        alignment: 0.3,
      );
    },
    pulseEnable: !sinAnimaciones,
    focusAnimationDuration: duracion,
    unFocusAnimationDuration: duracion,
    onFinish: terminar,
    onSkip: () {
      terminar();
      return true;
    },
  );
  tutorial.show(context: context);

  return true;
}

/// El cartel va debajo del elemento, salvo que esté en la mitad de abajo.
ContentAlign _alineacion(PasoTour paso, double altoPantalla) {
  final caja = paso.clave.currentContext?.findRenderObject();
  if (caja is! RenderBox || !caja.hasSize) return ContentAlign.bottom;
  final centro = caja.localToGlobal(Offset.zero).dy + caja.size.height / 2;
  return centro > altoPantalla / 2 ? ContentAlign.top : ContentAlign.bottom;
}

/// Lanza el tour de una pantalla cuando la guía lo ha encargado.
///
/// Ya no salta solo al entrar: o lo pide la guía con «Hacerlo ahora», o lo
/// pide el usuario con el botón de ayuda. Y el encargo caduca, para que
/// nunca aparezca un tour por sorpresa un rato después.
class TourPorEncargo extends ConsumerStatefulWidget {
  /// Los tours que esta pantalla sabe enseñar, con sus pasos.
  ///
  /// Casi siempre es uno, pero el detalle de factura enseña tres distintos
  /// según lo que haya pedido la guía.
  final Map<Tour, List<PasoTour> Function()> tours;

  /// Mientras la pantalla carga no se enseña nada.
  final bool listo;

  /// Para las pestañas: el tour de Facturas espera a que se vea la suya.
  final bool activo;

  final Widget child;

  TourPorEncargo({
    super.key,
    required Tour tour,
    required List<PasoTour> Function() pasos,
    required this.child,
    this.listo = true,
    this.activo = true,
  }) : tours = {tour: pasos};

  /// Para las pantallas que pueden enseñar más de un tour.
  const TourPorEncargo.varios({
    super.key,
    required this.tours,
    required this.child,
    this.listo = true,
    this.activo = true,
  });

  @override
  ConsumerState<TourPorEncargo> createState() => _TourPorEncargoState();
}

class _TourPorEncargoState extends ConsumerState<TourPorEncargo> {
  bool _lanzando = false;
  bool _encargoVivo = false;
  Tour? _encargado;
  TutorialNotifier? _tutorial;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hay que guardarlo: en dispose ya no se puede usar `ref`.
    _tutorial = ref.read(tutorialProvider.notifier);
  }

  @override
  void dispose() {
    // Si el usuario se va sin que el tour llegara a verse, el encargo muere
    // con la pantalla.
    if (_encargoVivo) unawaited(_tutorial?.olvidarEncargo() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(tutorialProvider).valueOrNull;
    final pendiente = datos?.tourPendiente;
    _encargoVivo = pendiente != null && widget.tours.containsKey(pendiente);
    final encargado =
        pendiente != null &&
        _encargoVivo &&
        (datos?.encargoVigente(pendiente) ?? false);

    if (encargado && widget.listo && widget.activo && !_lanzando) {
      _lanzando = true;
      _encargado = pendiente;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lanzar());
    }
    return widget.child;
  }

  Future<void> _lanzar() async {
    // Un respiro para que la pantalla acabe de pintarse.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final tour = _encargado;
    final pasos = tour == null ? null : widget.tours[tour];
    if (tour == null || pasos == null) return;

    await ref.read(tutorialProvider.notifier).olvidarEncargo();
    if (!mounted) return;
    await mostrarTour(context, ref, tour: tour, pasos: pasos());
  }
}
