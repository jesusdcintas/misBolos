import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/franja_bolo.dart';
import '../../models/gig.dart';
import 'facturable_badge.dart';
import 'franja_badge.dart';
import 'status_badge.dart';

/// Las etiquetas de un bolo, en un Wrap para que salten de línea.
///
/// La de franja solo existe si es Tarde o Noche, así que se omite cuando no
/// toca en vez de dejar un hueco vacío con su separación.
class GigBadges extends StatelessWidget {
  final Gig gig;

  const GigBadges({super.key, required this.gig});

  @override
  Widget build(BuildContext context) {
    final conFranja = gig.franja?.seEtiqueta ?? false;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        FacturableBadge(facturable: gig.facturable),
        if (conFranja) FranjaBadge(franja: gig.franja),
        StatusBadge(status: gig.status, facturable: gig.facturable),
      ],
    );
  }
}

/// Contenido de una tarjeta de bolo.
///
/// El nombre y el importe comparten la primera fila y las etiquetas van
/// debajo: con las tres a la vez y un nombre largo, meterlo todo en una fila
/// deja al nombre sin ancho y lo parte por sílabas.
class GigCardContent extends StatelessWidget {
  /// Nombre del cliente, ya resuelto.
  final String nombre;

  /// Línea de detalle bajo el nombre, por ejemplo la fecha.
  final String? detalle;

  /// Importe ya formateado.
  final String? importe;

  final Gig gig;

  /// Se pinta a la derecha del nombre, antes del importe.
  final Widget? extra;

  const GigCardContent({
    super.key,
    required this.nombre,
    required this.gig,
    this.detalle,
    this.importe,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (extra != null) ...[const SizedBox(width: 8), extra!],
            if (importe != null) ...[
              const SizedBox(width: 12),
              Text(
                importe!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ],
          ],
        ),
        if (detalle != null) ...[
          const SizedBox(height: 2),
          Text(
            detalle!,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        GigBadges(gig: gig),
      ],
    );
  }
}
