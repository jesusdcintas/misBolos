import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/dashboard_amounts.dart';
import '../../providers/stats_provider.dart';
import '../common/animated_counter.dart';

/// Tarjeta de ingresos del periodo, en azul marino.
///
/// Las tres cifras y la comparación son las que ya mostraba el resumen del
/// dashboard; la barra reparte el total previsto en cobrado, pendiente de cobro
/// y confirmado sin facturar.
class IncomePeriodCard extends StatelessWidget {
  final PeriodDashboardStats stats;
  final DashboardPeriod period;

  const IncomePeriodCard({
    super.key,
    required this.stats,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;

    final cobrado = stats.cobrado;
    final pendiente = stats.pendienteTotal;
    final total = stats.totalPrevistoGlobal;
    final confirmado = confirmadoSinFacturar(
      totalPrevisto: total,
      cobrado: cobrado,
      pendiente: pendiente,
    );

    return GestureDetector(
      onTap: () => context.push('/financial'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [primary, primary.withValues(alpha: 0.78)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ingresos · ${period.label}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Cifra(
                    label: 'Cobrado',
                    value: cobrado,
                    color: Colors.white,
                    extra: _comparacion(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Cifra(
                    label: 'Pendiente de cobro',
                    value: pendiente,
                    color: colors.warningBg,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Cifra(
                    label: 'Total previsto',
                    value: total,
                    color: colors.successBg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BarraTramos(
              cobrado: cobrado,
              pendiente: pendiente,
              confirmado: confirmado,
              colorCobrado: Colors.white,
              colorPendiente: colors.warningBg,
              colorConfirmado: Colors.white24,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _Leyenda(color: Colors.white, texto: 'Cobrado'),
                _Leyenda(color: colors.warningBg, texto: 'Pendiente'),
                const _Leyenda(
                  color: Colors.white24,
                  texto: 'Confirmado sin facturar',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Etiqueta(
                  texto: 'Oficial ${CurrencyFormatter.format(stats.totalPrevisto)}',
                ),
                _Etiqueta(
                  texto:
                      'Privado ${CurrencyFormatter.format(stats.totalPrevistoEnB)}',
                ),
                _Etiqueta(
                  texto:
                      '${stats.totalBolos} bolo${stats.totalBolos == 1 ? '' : 's'}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Comparación de lo cobrado con el periodo anterior, la que ya existía.
  Widget? _comparacion() {
    final prev = stats.prevCobrado;
    final label = stats.prevLabel;
    if (prev == null || label == null) return null;
    final current = stats.cobrado;
    if (prev == 0 && current == 0) return null;

    final pct = prev > 0 ? ((current - prev) / prev * 100).round() : 100;
    final isUp = pct >= 0;
    return Text(
      '${isUp ? '↑' : '↓'} ${isUp ? '+' : ''}$pct% vs $label',
      style: TextStyle(
        fontSize: 11,
        color: isUp ? Colors.greenAccent[100] : Colors.redAccent[100],
      ),
    );
  }
}

class _Cifra extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final Widget? extra;

  const _Cifra({
    required this.label,
    required this.value,
    required this.color,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
        ),
        const SizedBox(height: 2),
        AnimatedCounter(
          value: value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        if (extra != null) ...[const SizedBox(height: 4), extra!],
      ],
    );
  }
}

/// Barra de tres tramos proporcional al total previsto.
class _BarraTramos extends StatelessWidget {
  final double cobrado;
  final double pendiente;
  final double confirmado;
  final Color colorCobrado;
  final Color colorPendiente;
  final Color colorConfirmado;

  const _BarraTramos({
    required this.cobrado,
    required this.pendiente,
    required this.confirmado,
    required this.colorCobrado,
    required this.colorPendiente,
    required this.colorConfirmado,
  });

  @override
  Widget build(BuildContext context) {
    final total = cobrado + pendiente + confirmado;
    if (total <= 0) {
      return Container(
        height: 10,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            if (cobrado > 0)
              Expanded(
                flex: (cobrado / total * 1000).round(),
                child: ColoredBox(color: colorCobrado),
              ),
            if (pendiente > 0)
              Expanded(
                flex: (pendiente / total * 1000).round(),
                child: ColoredBox(color: colorPendiente),
              ),
            if (confirmado > 0)
              Expanded(
                flex: (confirmado / total * 1000).round(),
                child: ColoredBox(color: colorConfirmado),
              ),
          ],
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;

  const _Leyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          texto,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;

  const _Etiqueta({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
