import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/fechas_libres.dart';

const _iniciales = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

/// Rejilla del mes con los días marcados, los ocupados y los ya pasados.
///
/// Tocar un día llama a [onTocarDia] con su clave normalizada.
class MiniCalendarioMes extends StatelessWidget {
  final int year;
  final int month;

  /// Días que entran en el texto.
  final Set<DateTime> marcados;

  /// Días con algún bolo: se atenúan y llevan un punto.
  final Set<DateTime> ocupados;

  /// Hoy, para atenuar lo ya pasado. Solo se pasa en los tests.
  final DateTime? hoy;

  final ValueChanged<DateTime> onTocarDia;

  const MiniCalendarioMes({
    super.key,
    required this.year,
    required this.month,
    required this.marcados,
    required this.ocupados,
    required this.onTocarDia,
    this.hoy,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final desde = diaClave(hoy ?? DateTime.now());
    final primero = DateTime.utc(year, month, 1);
    final ultimoDia = DateTime.utc(year, month + 1, 0).day;
    // weekday: 1 lunes … 7 domingo. La rejilla empieza en lunes.
    final huecosIniciales = primero.weekday - 1;

    final celdas = <Widget>[
      for (final inicial in _iniciales)
        Center(
          child: Text(
            inicial,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
      for (var i = 0; i < huecosIniciales; i++) const SizedBox.shrink(),
      for (var dia = 1; dia <= ultimoDia; dia++)
        _Dia(
          fecha: DateTime.utc(year, month, dia),
          marcado: marcados.contains(DateTime.utc(year, month, dia)),
          ocupado: ocupados.contains(DateTime.utc(year, month, dia)),
          pasado: DateTime.utc(year, month, dia).isBefore(desde),
          onTocar: onTocarDia,
        ),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: celdas,
    );
  }
}

class _Dia extends StatelessWidget {
  final DateTime fecha;
  final bool marcado;
  final bool ocupado;
  final bool pasado;
  final ValueChanged<DateTime> onTocar;

  const _Dia({
    required this.fecha,
    required this.marcado,
    required this.ocupado,
    required this.pasado,
    required this.onTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    final atenuado = ocupado || pasado;

    final Color fondo;
    final Color texto;
    if (marcado && !atenuado) {
      fondo = primary;
      texto = Colors.white;
    } else if (atenuado) {
      fondo = colors.surfaceContainer.withValues(alpha: 0.5);
      texto = colors.textMuted;
    } else {
      fondo = colors.surfaceContainer;
      texto = colors.textPrimary;
    }

    return InkWell(
      onTap: pasado ? null : () => onTocar(fecha),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(8),
          border: marcado && atenuado
              ? Border.all(color: primary.withValues(alpha: 0.5), width: 1.5)
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${fecha.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: marcado ? FontWeight.bold : FontWeight.normal,
                color: texto,
              ),
            ),
            if (ocupado)
              Positioned(
                bottom: 3,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.warning,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
