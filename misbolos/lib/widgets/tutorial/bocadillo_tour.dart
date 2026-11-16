import 'package:flutter/material.dart';

import '../../core/services/hapticos.dart';
import '../../core/theme/app_theme_colors.dart';

/// El cartel que explica cada paso de un tour.
///
/// Va encima del velo, así que se pinta con los colores del tema para que se
/// lea igual de bien en claro y en oscuro.
class BocadilloTour extends StatelessWidget {
  /// Empieza en 1: es lo que ve el usuario en «2 de 4».
  final int numero;
  final int total;
  final String texto;
  final VoidCallback alSiguiente;
  final VoidCallback alSaltar;

  const BocadilloTour({
    super.key,
    required this.numero,
    required this.total,
    required this.texto,
    required this.alSiguiente,
    required this.alSaltar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  texto,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '$numero de $total',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Hapticos.toque();
                        alSaltar();
                      },
                      child: Text(
                        'Saltar',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () {
                        Hapticos.seleccion();
                        alSiguiente();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                      ),
                      child: const Text('Siguiente'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
