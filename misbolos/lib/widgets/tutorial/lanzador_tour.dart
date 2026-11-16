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

  TutorialCoachMark(
    targets: [
      for (final (indice, paso) in visibles.indexed)
        TargetFocus(
          identify: '${tour.name}-$indice',
          keyTarget: paso.clave,
          shape: paso.redondo ? ShapeLightFocus.Circle : ShapeLightFocus.RRect,
          radius: 14,
          enableTargetTab: false,
          contents: [
            TargetContent(
              align: _alineacion(paso, alto),
              builder: (context, controlador) => BocadilloTour(
                numero: indice + 1,
                total: visibles.length,
                texto: paso.texto,
                alSiguiente: controlador.next,
                alSaltar: controlador.skip,
              ),
            ),
          ],
        ),
    ],
    colorShadow: scheme.scrim,
    opacityShadow: 0.72,
    paddingFocus: 8,
    // El botón de saltar va dentro del bocadillo, junto al progreso.
    hideSkip: true,
    pulseEnable: !sinAnimaciones,
    focusAnimationDuration: duracion,
    unFocusAnimationDuration: duracion,
    onFinish: terminar,
    onSkip: () {
      terminar();
      return true;
    },
  ).show(context: context);

  return true;
}

/// El cartel va debajo del elemento, salvo que esté en la mitad de abajo.
ContentAlign _alineacion(PasoTour paso, double altoPantalla) {
  final caja = paso.clave.currentContext?.findRenderObject();
  if (caja is! RenderBox || !caja.hasSize) return ContentAlign.bottom;
  final centro = caja.localToGlobal(Offset.zero).dy + caja.size.height / 2;
  return centro > altoPantalla / 2 ? ContentAlign.top : ContentAlign.bottom;
}

/// Lanza el tour de una pantalla la primera vez que se entra en ella.
///
/// [listo] evita que salte mientras la pantalla carga, y [activo] sirve para
/// las pestañas: el tour de Facturas no debe saltar hasta que su pestaña esté
/// a la vista.
class TourAlEntrar extends ConsumerStatefulWidget {
  final Tour tour;
  final List<PasoTour> Function() pasos;
  final bool listo;
  final bool activo;
  final Widget child;

  const TourAlEntrar({
    super.key,
    required this.tour,
    required this.pasos,
    required this.child,
    this.listo = true,
    this.activo = true,
  });

  @override
  ConsumerState<TourAlEntrar> createState() => _TourAlEntrarState();
}

class _TourAlEntrarState extends ConsumerState<TourAlEntrar> {
  bool _lanzando = false;
  int _intentos = 0;

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(tutorialProvider).valueOrNull;
    final toca = datos?.tocaMostrar(widget.tour) ?? false;

    if (toca && widget.listo && widget.activo && !_lanzando) {
      _lanzando = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lanzar());
    }
    return widget.child;
  }

  Future<void> _lanzar() async {
    // Un respiro para que la pantalla acabe de pintarse y para no pisar la
    // animación de entrada.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    final mostrado = await mostrarTour(
      context,
      ref,
      tour: widget.tour,
      pasos: widget.pasos(),
    );
    if (mostrado || _intentos >= 2) return;

    // Había otro tour abierto o aún no estaba el elemento: se reintenta un
    // par de veces y se deja estar.
    _intentos++;
    if (mounted) setState(() => _lanzando = false);
  }
}
