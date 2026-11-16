import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/estado_tutorial.dart';
import '../../core/services/hapticos.dart';
import 'lanzador_tour.dart';
import 'tour.dart';

const textoAyudaTour = 'Ver el tutorial de esta pantalla';
const etiquetaMenuAyudaTour = 'Ver tutorial';

/// Vuelve a enseñar el tour de esta pantalla cuando al usuario le apetezca.
///
/// No toca nada de lo guardado: ni marca este tour como visto ni cambia el de
/// las demás pantallas.
Future<void> verTutorialDePantalla(
  BuildContext context,
  WidgetRef ref, {
  required Tour tour,
  required List<PasoTour> pasos,
}) {
  Hapticos.toque();
  return mostrarTour(
    context,
    ref,
    tour: tour,
    pasos: pasos,
    guardarVisto: false,
  );
}

/// El botón de ayuda de la barra superior.
class BotonAyudaTour extends ConsumerWidget {
  final Tour tour;
  final List<PasoTour> Function() pasos;

  const BotonAyudaTour({super.key, required this.tour, required this.pasos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.help_outline),
      tooltip: textoAyudaTour,
      onPressed: () =>
          verTutorialDePantalla(context, ref, tour: tour, pasos: pasos()),
    );
  }
}
