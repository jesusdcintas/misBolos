import 'package:flutter/material.dart';

import '../../core/services/hapticos.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/primeros_pasos.dart';

/// La lista de primeros pasos de Inicio, para quien acaba de empezar.
///
/// No sabe de dónde salen los datos: recibe los pasos ya resueltos, así se
/// puede pintar en un test sin base ni nube.
class TarjetaPrimerosPasos extends StatelessWidget {
  final List<EstadoPasoInicial> pasos;
  final ValueChanged<PasoInicial> alTocarPaso;
  final VoidCallback alOcultar;

  const TarjetaPrimerosPasos({
    super.key,
    required this.pasos,
    required this.alTocarPaso,
    required this.alOcultar,
  });

  @override
  Widget build(BuildContext context) {
    // Con todo hecho, la tarjeta ya no pinta nada.
    if (pasos.isEmpty || primerosPasosTerminados(pasos)) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Primeros pasos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${pasosCompletados(pasos)} de ${pasos.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 4),
            for (final estado in pasos)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: estado.completado
                    ? null
                    : () {
                        Hapticos.toque();
                        alTocarPaso(estado.paso);
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        estado.completado
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: estado.completado
                            ? colors.success
                            : colors.textMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          estado.paso.titulo,
                          style: TextStyle(
                            fontSize: 14,
                            color: estado.completado
                                ? colors.textSecondary
                                : colors.textPrimary,
                            decoration: estado.completado
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: colors.textSecondary,
                          ),
                        ),
                      ),
                      if (!estado.completado)
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: colors.textMuted,
                        ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Hapticos.toque();
                  alOcultar();
                },
                child: Text('Ocultar', style: TextStyle(color: scheme.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
