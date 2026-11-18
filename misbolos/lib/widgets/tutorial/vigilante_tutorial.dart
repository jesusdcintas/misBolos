import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/estado_tutorial.dart';
import '../../providers/tutorial_provider.dart';

/// Decide, una sola vez por instalación, si quien abre la app ya la usaba.
///
/// Vive en el armazón de las pestañas para que dé igual en cuál se entre
/// primero. Mientras no se pueda decidir no escribe nada, así que una
/// descarga fallida se reintenta en la siguiente apertura.
class VigilanteTutorial extends ConsumerWidget {
  final Widget child;

  const VigilanteTutorial({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(decisionTutorialProvider);
    if (decision != DecisionTutorial.esperar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(tutorialProvider.notifier).aplicarDecision(decision);
      });
    }
    return child;
  }
}
