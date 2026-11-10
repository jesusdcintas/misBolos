import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/fechas_libres.dart';

final _diaCorto = DateFormat('EEE', 'es');

/// Estado en el que se pinta cada celda.
enum _EstadoDia { pasado, parcial, conBolo, marcado, hoy, normal }

/// Rejilla del mes con los días marcados, los que tienen bolo y los pasados.
///
/// Tocar un día llama a [onTocarDia] con su clave normalizada.
class MiniCalendarioMes extends StatelessWidget {
  final int year;
  final int month;

  /// Días enteros libres que entran en el texto.
  final Set<DateTime> marcados;

  /// Día con solo media franja libre y cuál: «Tarde» o «Noche».
  final Map<DateTime, String> parciales;

  /// Día con bolo y el texto que describe quién, para el tooltip.
  final Map<DateTime, String> bolosPorDia;

  /// Alto de cada celda. 52 en escritorio y 46 en móvil.
  final double altoCelda;

  /// Hoy. Solo se pasa en los tests.
  final DateTime? hoy;

  final ValueChanged<DateTime> onTocarDia;

  const MiniCalendarioMes({
    super.key,
    required this.year,
    required this.month,
    required this.marcados,
    required this.bolosPorDia,
    this.parciales = const {},
    required this.onTocarDia,
    this.altoCelda = 52,
    this.hoy,
  });

  static const double _separacion = 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hoyClave = diaClave(hoy ?? DateTime.now());
    final primero = DateTime.utc(year, month, 1);
    final ultimoDia = DateTime.utc(year, month + 1, 0).day;
    // weekday: 1 lunes … 7 domingo. La rejilla empieza en lunes.
    final huecosIniciales = primero.weekday - 1;
    final totalCeldas = huecosIniciales + ultimoDia;
    final semanas = (totalCeldas / 7).ceil();

    return Column(
      children: [
        // Una sola cabecera con los nombres cortos, de intl.
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _diaCorto
                        .format(DateTime.utc(2026, 1, 5 + i))
                        .replaceAll('.', ''),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var semana = 0; semana < semanas; semana++) ...[
          SizedBox(
            height: altoCelda,
            child: Row(
              children: [
                for (var columna = 0; columna < 7; columna++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _separacion / 2,
                      ),
                      child: _celda(
                        semana * 7 + columna - huecosIniciales,
                        ultimoDia,
                        hoyClave,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (semana < semanas - 1) const SizedBox(height: _separacion),
        ],
      ],
    );
  }

  Widget _celda(int dia, int ultimoDia, DateTime hoyClave) {
    if (dia < 1 || dia > ultimoDia) return const SizedBox.shrink();

    final fecha = DateTime.utc(year, month, dia);
    final cliente = bolosPorDia[fecha];
    final pasado = fecha.isBefore(hoyClave);

    final parcial = parciales[fecha];

    final _EstadoDia estado;
    if (pasado) {
      estado = _EstadoDia.pasado;
    } else if (parcial != null) {
      // Media franja libre manda sobre el bolo: es lo que se puede ofrecer.
      estado = _EstadoDia.parcial;
    } else if (cliente != null) {
      estado = _EstadoDia.conBolo;
    } else if (marcados.contains(fecha)) {
      estado = _EstadoDia.marcado;
    } else if (fecha == hoyClave) {
      estado = _EstadoDia.hoy;
    } else {
      estado = _EstadoDia.normal;
    }

    return _Celda(
      fecha: fecha,
      estado: estado,
      cliente: cliente,
      etiquetaParcial: parcial,
      onTocar: pasado ? null : () => onTocarDia(fecha),
    );
  }
}

class _Celda extends StatelessWidget {
  final DateTime fecha;
  final _EstadoDia estado;
  final String? cliente;
  final String? etiquetaParcial;
  final VoidCallback? onTocar;

  const _Celda({
    required this.fecha,
    required this.estado,
    this.cliente,
    this.etiquetaParcial,
    this.onTocar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;

    final Color fondo;
    final Color texto;
    Border? borde;
    String? etiqueta;

    switch (estado) {
      case _EstadoDia.marcado:
        fondo = primary;
        texto = Colors.white;
      case _EstadoDia.parcial:
        fondo = primary.withValues(alpha: 0.08);
        texto = primary;
        borde = Border.all(color: primary, width: 1.5);
        etiqueta = etiquetaParcial;
      case _EstadoDia.conBolo:
        fondo = colors.warningBg;
        texto = colors.warning;
        borde = Border.all(color: colors.warning, width: 1.2);
        etiqueta = 'Bolo';
      case _EstadoDia.pasado:
        fondo = colors.surfaceContainer;
        texto = colors.textMuted;
      case _EstadoDia.hoy:
        fondo = Colors.transparent;
        texto = primary;
        borde = Border.all(color: primary, width: 1.5);
        etiqueta = 'Hoy';
      case _EstadoDia.normal:
        fondo = Colors.transparent;
        texto = colors.textPrimary;
        borde = Border.all(color: colors.border, width: 0.6);
    }

    final celda = InkWell(
      onTap: onTocar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(10),
          border: borde,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${fecha.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: estado == _EstadoDia.marcado
                    ? FontWeight.bold
                    : FontWeight.w500,
                color: texto,
              ),
            ),
            if (etiqueta != null)
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: texto,
                ),
              ),
          ],
        ),
      ),
    );

    // El tooltip del cliente solo tiene sentido con ratón.
    final nombre = cliente;
    final conTooltip =
        estado == _EstadoDia.conBolo || estado == _EstadoDia.parcial;
    if (conTooltip && nombre != null && nombre.isNotEmpty) {
      return Tooltip(message: nombre, child: celda);
    }
    return celda;
  }
}

/// Leyenda de los estados del calendario.
class LeyendaMiniCalendario extends StatelessWidget {
  const LeyendaMiniCalendario({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;

    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _Muestra(color: primary, texto: 'Libre'),
        _Muestra(
          color: primary.withValues(alpha: 0.08),
          borde: primary,
          texto: 'Media libre',
        ),
        _Muestra(
          color: colors.warningBg,
          borde: colors.warning,
          texto: 'Con bolo',
        ),
        _Muestra(color: colors.surfaceContainer, texto: 'Pasado'),
      ],
    );
  }
}

class _Muestra extends StatelessWidget {
  final Color color;
  final Color? borde;
  final String texto;

  const _Muestra({required this.color, this.borde, required this.texto});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: borde != null ? Border.all(color: borde!, width: 1) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          texto,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
      ],
    );
  }
}
