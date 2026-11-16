import 'package:flutter/material.dart';

import '../../core/services/hapticos.dart';

/// Deslizar a los lados para ir al anterior o al siguiente.
///
/// Un callback a null significa que por ahí no se puede ir, y entonces el
/// gesto no hace nada: así los límites viven en quien lo usa.
///
/// Solo reacciona al gesto horizontal, de modo que no estorba al scroll
/// vertical de la pantalla.
class DeslizarHorizontal extends StatelessWidget {
  final Widget child;

  /// Deslizar hacia la derecha. Null si no se puede retroceder.
  final VoidCallback? onAnterior;

  /// Deslizar hacia la izquierda. Null si no se puede avanzar.
  final VoidCallback? onSiguiente;

  /// Velocidad mínima para que cuente, en píxeles por segundo.
  final double velocidadMinima;

  const DeslizarHorizontal({
    super.key,
    required this.child,
    this.onAnterior,
    this.onSiguiente,
    this.velocidadMinima = 220,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (detalles) {
        final velocidad = detalles.primaryVelocity ?? 0;
        if (velocidad.abs() < velocidadMinima) return;

        final destino = velocidad > 0 ? onAnterior : onSiguiente;
        if (destino == null) return;

        Hapticos.seleccion();
        destino();
      },
      child: child,
    );
  }
}
