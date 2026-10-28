import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/dashboard_amounts.dart';
import '../../providers/stats_provider.dart';
import '../common/animated_counter.dart';

/// Azul marino fijo: la tarjeta es una superficie oscura en los dos temas, así
/// que no puede usar colorScheme.primary (en oscuro es un azul claro) ni los
/// colores del tema, que en oscuro no se leen sobre el marino.
const Color _marino = AppColors.primary;

/// Colores de los tramos de la barra, legibles sobre el marino.
const Color _verdeCobrado = Color(0xFF4DBA7B);
const Color _ambarPendiente = Color(0xFFF0B35A);
const Color _grisConfirmado = Colors.white38;

/// Tonos claros para las cifras, los mismos que se veían en modo claro.
const Color _cremaPendiente = Color(0xFFFEF3E2);
const Color _mentaPrevisto = Color(0xFFE8F6EF);

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
            colors: [_marino, _marino.withValues(alpha: 0.88)],
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
                    color: _cremaPendiente,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Cifra(
                    label: 'Total previsto',
                    value: total,
                    color: _mentaPrevisto,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BarraTramos(
              cobrado: cobrado,
              pendiente: pendiente,
              confirmado: confirmado,
            ),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                // Cada punto lleva el color de su tramo en la barra.
                _Leyenda(color: _verdeCobrado, texto: 'Cobrado'),
                _Leyenda(color: _ambarPendiente, texto: 'Pendiente'),
                _Leyenda(
                  color: _grisConfirmado,
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

  /// Alto de la barra.
  static const double alto = 10;

  const _BarraTramos({
    required this.cobrado,
    required this.pendiente,
    required this.confirmado,
  });

  @override
  Widget build(BuildContext context) {
    final total = cobrado + pendiente + confirmado;
    if (total <= 0) {
      return Container(
        height: alto,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: alto,
        child: Row(
          // Sin stretch, la Row pasa restricciones verticales holgadas y un
          // ColoredBox sin hijo se queda en 0 de alto: la barra desaparecía.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cobrado > 0)
              Expanded(
                flex: (cobrado / total * 1000).round(),
                child: const ColoredBox(color: _verdeCobrado),
              ),
            if (pendiente > 0)
              Expanded(
                flex: (pendiente / total * 1000).round(),
                child: const ColoredBox(color: _ambarPendiente),
              ),
            if (confirmado > 0)
              Expanded(
                flex: (confirmado / total * 1000).round(),
                child: const ColoredBox(color: _grisConfirmado),
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
