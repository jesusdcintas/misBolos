import 'package:flutter/material.dart';

import '../../core/services/hapticos.dart';
import '../../core/theme/app_theme_colors.dart';

/// Lo que se enseña cuando la guía ya está hecha.
class CierreGuia extends StatelessWidget {
  final VoidCallback alOcultar;

  const CierreGuia({super.key, required this.alOcultar});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: colors.success, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ya está: la guía está completa',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '¿Era una factura de prueba? Bórrala desde su detalle y la '
              'siguiente volverá a tener ese número.',
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              'Tres sitios que conviene conocer:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            for (final (icono, texto) in const [
              (
                Icons.account_balance_outlined,
                'En Inicio tienes los impuestos estimados: lo que conviene '
                    'reservar para Hacienda.',
              ),
              (
                Icons.event_available_outlined,
                'En la Agenda, Fechas libres te arma el texto de tus días '
                    'libres para mandarlo por WhatsApp.',
              ),
              (
                Icons.help_outline,
                'El botón «?» de cada pantalla te vuelve a enseñar su '
                    'tutorial cuando quieras.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icono, size: 18, color: colors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        texto,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Hapticos.toque();
                  alOcultar();
                },
                child: const Text('Ocultar la guía'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
