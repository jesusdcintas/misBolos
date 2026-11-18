import 'package:flutter/material.dart';

import '../../core/services/guia_inicio.dart';
import '../../core/services/hapticos.dart';
import '../../core/theme/app_theme_colors.dart';

/// La guía de inicio de la pantalla de Inicio.
///
/// No sabe de dónde salen los datos: recibe los pasos ya resueltos, así se
/// puede pintar en un test sin base ni nube.
class TarjetaGuiaInicio extends StatelessWidget {
  final List<EstadoPasoGuia> pasos;

  /// El paso que toca ahora, que es el único que sale desplegado.
  final PasoGuia? siguiente;

  final void Function(PasoGuia) alHacerlo;
  final void Function(PasoGuia) alSaltar;
  final VoidCallback alOcultar;

  /// Para quien ya tiene sus datos en una hoja de cálculo.
  final VoidCallback alImportar;

  const TarjetaGuiaInicio({
    super.key,
    required this.pasos,
    required this.siguiente,
    required this.alHacerlo,
    required this.alSaltar,
    required this.alOcultar,
    required this.alImportar,
  });

  @override
  Widget build(BuildContext context) {
    if (pasos.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final hechos = pasosCerrados(pasos);

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
                    'Guía de inicio',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '$hechos de ${pasos.length}',
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
              _Paso(
                estado: estado,
                abierto: estado.paso == siguiente,
                alHacerlo: () => alHacerlo(estado.paso),
                alSaltar: () => alSaltar(estado.paso),
                alImportar: alImportar,
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

class _Paso extends StatelessWidget {
  final EstadoPasoGuia estado;
  final bool abierto;
  final VoidCallback alHacerlo;
  final VoidCallback alSaltar;
  final VoidCallback alImportar;

  const _Paso({
    required this.estado,
    required this.abierto,
    required this.alHacerlo,
    required this.alSaltar,
    required this.alImportar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final paso = estado.paso;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                estado.hecho
                    ? Icons.check_circle
                    : estado.saltado
                    ? Icons.remove_circle_outline
                    : Icons.radio_button_unchecked,
                size: 20,
                color: estado.hecho
                    ? colors.success
                    : estado.saltado
                    ? colors.textMuted
                    : colors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paso.titulo,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: abierto ? FontWeight.w700 : FontWeight.w400,
                        color: estado.cerrado
                            ? colors.textSecondary
                            : colors.textPrimary,
                        decoration: estado.cerrado
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: colors.textSecondary,
                      ),
                    ),
                    if (abierto) ...[
                      const SizedBox(height: 2),
                      Text(
                        estado.enCurso ? 'Sincronizando…' : paso.detalle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (abierto && !estado.enCurso)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: () {
                      Hapticos.toque();
                      alHacerlo();
                    },
                    child: const Text('Hacerlo ahora'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      Hapticos.toque();
                      alSaltar();
                    },
                    child: Text(
                      'Saltar este paso',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          if (abierto && paso == PasoGuia.cliente)
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: TextButton(
                onPressed: () {
                  Hapticos.toque();
                  alImportar();
                },
                child: const Text(
                  '¿Ya tienes clientes y bolos en Excel? Impórtalos',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
