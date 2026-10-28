import 'package:flutter/material.dart';
import '../../core/config/fiscal.dart';

/// Abre la información de la retención de IRPF.
///
/// Hoja inferior en móvil y diálogo en pantallas anchas, con el mismo corte de
/// 700 px que ya usa la pantalla de Ajustes para pasar a dos columnas.
Future<void> mostrarRetencionIrpfInfo(BuildContext context) {
  if (MediaQuery.of(context).size.width >= 700) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: RetencionIrpfInfo(),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: RetencionIrpfInfo(),
      ),
    ),
  );
}

/// Contenido de la ventana que explica qué retención corresponde a cada factura.
///
/// Los textos salen de [RetencionIrpf], no se duplican aquí.
class RetencionIrpfInfo extends StatelessWidget {
  const RetencionIrpfInfo({super.key});

  static const String titulo = 'Retención IRPF en tus facturas';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        // De mayor a menor: 15 %, 7 % y 0 %.
        for (final rate in RetencionIrpf.opciones.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OpcionRetencion(rate: rate),
          ),
        const SizedBox(height: 4),
        const RetencionIrpfAviso(),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ),
      ],
    );
  }
}

/// Una opción de retención: el porcentaje en grande y su explicación debajo.
class _OpcionRetencion extends StatelessWidget {
  final double rate;

  const _OpcionRetencion({required this.rate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            RetencionIrpf.etiqueta(rate),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            RetencionIrpf.explicacion(rate)!,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Recuadro destacado con la nota del 20 % y, si se pasa [rate], la explicación
/// del tipo elegido. Un [rate] que no sea una opción válida muestra un aviso.
///
/// Mismo estilo que el recuadro de «¿Es facturable?» del formulario de bolo,
/// pero con colores del tema para que funcione en claro y en oscuro.
class RetencionIrpfAviso extends StatelessWidget {
  final double? rate;

  const RetencionIrpfAviso({super.key, this.rate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rate = this.rate;
    final valida = rate == null || RetencionIrpf.esValida(rate);
    final color = valida
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    final String? explicacion;
    if (rate == null) {
      explicacion = null;
    } else if (valida) {
      explicacion = RetencionIrpf.explicacion(rate);
    } else {
      explicacion =
          'Tienes guardado un ${RetencionIrpf.etiqueta(rate)} que ya no es '
          'una opción. Elige una de las de arriba.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            valida ? Icons.info_outline : Icons.warning_amber_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (explicacion != null) ...[
                  Text(
                    explicacion,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.35,
                      color: valida ? null : color,
                      fontWeight: valida ? null : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  RetencionIrpf.notaGeneral,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
