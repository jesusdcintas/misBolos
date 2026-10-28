import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/stats_provider.dart';

/// Facturas emitidas y sin cobrar del periodo, de la más antigua a la más
/// nueva. Resalta en ámbar las que llevan más de 7 días.
class PendingInvoicesCard extends StatelessWidget {
  final List<PendingInvoice> pendientes;

  /// Cuántas se listan como máximo.
  static const int maximo = 3;

  const PendingInvoicesCard({super.key, required this.pendientes});

  @override
  Widget build(BuildContext context) {
    // Sin facturas pendientes la sección no aparece.
    if (pendientes.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final theme = Theme.of(context);
    final visibles = pendientes.take(maximo).toList();
    final total = pendientes.fold<double>(
      0,
      (suma, p) => suma + p.invoice.total,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pendiente de cobro',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/finanzas'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Facturas →'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border, width: 0.6),
          ),
          child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final p in visibles) ...[
                      _Fila(pendiente: p),
                      if (p != visibles.last) const SizedBox(height: 10),
                    ],
                    if (pendientes.length > visibles.length) ...[
                      const SizedBox(height: 10),
                      Text(
                        'y ${pendientes.length - visibles.length} más',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    Divider(height: 24, color: colors.border),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total pendiente',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(total),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colors.warning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  final PendingInvoice pendiente;

  const _Fila({required this.pendiente});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dias = pendiente.daysSinceSent;
    final vencida = dias > 7;

    return InkWell(
      onTap: () => context.push('/invoice/${pendiente.invoice.id}'),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pendiente.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.format(pendiente.invoice.total),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: vencida ? colors.warningBg : colors.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              dias == 0 ? 'hoy' : 'hace $dias día${dias == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: vencida ? colors.warning : colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
