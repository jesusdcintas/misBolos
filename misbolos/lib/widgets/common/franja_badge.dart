import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/franja_bolo.dart';

/// Etiqueta con la franja del bolo.
///
/// Solo se pinta si es Tarde o Noche: «Todo el día» y los bolos sin franja no
/// llevan etiqueta, para no añadir ruido a las listas.
class FranjaBadge extends StatelessWidget {
  final FranjaBolo? franja;

  const FranjaBadge({super.key, required this.franja});

  @override
  Widget build(BuildContext context) {
    final franja = this.franja;
    if (franja == null || !franja.seEtiqueta) return const SizedBox.shrink();

    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colors.infoBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            franja == FranjaBolo.tarde
                ? Icons.wb_twilight
                : Icons.nightlight_outlined,
            size: 11,
            color: colors.info,
          ),
          const SizedBox(width: 4),
          Text(
            franja.label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: colors.info,
            ),
          ),
        ],
      ),
    );
  }
}
