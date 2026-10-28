import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/dashboard_amounts.dart';
import '../../core/utils/fiscal_deadlines.dart';
import '../../models/financial_summary.dart';
import '../../providers/stats_provider.dart';

/// Impuestos estimados del periodo.
///
/// Usa el mismo [FinancialSummary] que la pantalla de Finanzas, calculado por
/// `financialSummaryProvider` con el periodo de Inicio: aquí no se calcula
/// ningún impuesto, solo se presenta.
class TaxesPeriodCard extends StatelessWidget {
  final FinancialSummary summary;
  final DashboardPeriod period;

  const TaxesPeriodCard({
    super.key,
    required this.summary,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final reserva = reservaParaHacienda(
      ivaRepercutido: summary.ivaRepercutidoBruto,
      irpfAIngresar: summary.irpfAIngresar,
    );
    final plazo = resolverPlazoModelo130(
      year: period.year,
      quarter: _trimestreDelPeriodo(period),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Impuestos estimados · ${period.label}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Reserva para Hacienda',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            CurrencyFormatter.format(reserva),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.warning,
            ),
          ),
          const SizedBox(height: 16),
          _Linea(
            label: 'IVA repercutido',
            value: summary.ivaRepercutidoBruto,
          ),
          const SizedBox(height: 8),
          _Linea(
            // En la vista Año no es un pago trimestral, son los cuatro.
            label: period.mode == DashboardPeriodMode.anio
                ? 'IRPF pagos fraccionados (20 %)'
                : 'IRPF pago trimestral (20 %)',
            value: summary.irpfTeorico,
          ),
          const SizedBox(height: 8),
          _Linea(
            label: 'Ya retenido por clientes',
            value: -summary.irpfRetenido,
            negativo: true,
          ),
          if (summary.retencionSuperaIrpf) ...[
            const SizedBox(height: 6),
            Text(
              'Los clientes han retenido más IRPF del que corresponde en este '
              'periodo',
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.infoBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  plazo.cerrado
                      ? Icons.event_busy_outlined
                      : Icons.event_outlined,
                  size: 16,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plazo.texto,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Estimación orientativa sobre facturas emitidas, sin restar '
            'gastos. Confírmala con tu gestoría.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push('/financial'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Ver detalle →'),
            ),
          ),
        ],
      ),
    );
  }

  /// Trimestre que se declara según el periodo. Null en el modo Año.
  static int? _trimestreDelPeriodo(DashboardPeriod period) {
    switch (period.mode) {
      case DashboardPeriodMode.mes:
        return ((period.month - 1) ~/ 3) + 1;
      case DashboardPeriodMode.trimestre:
        return period.quarter;
      case DashboardPeriodMode.anio:
        return null;
    }
  }
}

class _Linea extends StatelessWidget {
  final String label;
  final double value;
  final bool negativo;

  const _Linea({
    required this.label,
    required this.value,
    this.negativo = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: colors.textPrimary),
          ),
        ),
        Text(
          CurrencyFormatter.format(value),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: negativo ? colors.success : colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
