import 'package:flutter/material.dart';

import '../../core/services/hapticos.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../models/gig.dart';
import '../../models/invoice.dart';

/// Acciones del menú rápido de un bolo.
enum AccionBolo { ver, editar, duplicar, facturar, verFactura, cancelar }

/// Acciones del menú rápido de una factura.
///
/// Emitir, borrar y rectificar no están a propósito: son acciones fiscales y
/// se quedan en el detalle, con su confirmación.
enum AccionFactura { ver, compartirPdf, enviarEmail, marcarCobrada }

/// Qué acciones tiene sentido ofrecer para [gig].
List<AccionBolo> accionesDeBolo(Gig gig) {
  final tieneFactura = gig.invoiceId?.trim().isNotEmpty ?? false;
  final cancelado = gig.status == GigStatus.cancelado;
  return [
    AccionBolo.ver,
    AccionBolo.editar,
    AccionBolo.duplicar,
    if (gig.facturable && !tieneFactura && !cancelado) AccionBolo.facturar,
    if (tieneFactura) AccionBolo.verFactura,
    if (!cancelado) AccionBolo.cancelar,
  ];
}

/// Qué acciones tiene sentido ofrecer para [invoice].
List<AccionFactura> accionesDeFactura(
  Invoice invoice, {
  required bool puedeEnviarEmail,
}) {
  return [
    AccionFactura.ver,
    AccionFactura.compartirPdf,
    if (puedeEnviarEmail) AccionFactura.enviarEmail,
    if (invoice.status == InvoiceStatus.enviada) AccionFactura.marcarCobrada,
  ];
}

/// Una entrada del menú.
@immutable
class AccionRapida {
  final IconData icono;
  final String etiqueta;

  /// Null para el color de texto normal.
  final Color? color;
  final VoidCallback alPulsar;

  const AccionRapida({
    required this.icono,
    required this.etiqueta,
    required this.alPulsar,
    this.color,
  });
}

/// Abre el menú: hoja inferior en móvil y menú contextual en escritorio.
Future<void> mostrarMenuAcciones(
  BuildContext context, {
  required List<AccionRapida> acciones,
  Offset? posicion,
}) async {
  if (acciones.isEmpty) return;
  Hapticos.toque();

  final esEscritorio = MediaQuery.of(context).size.width >= 700;
  if (esEscritorio && posicion != null) {
    final pantalla = Overlay.of(context).context.size ?? Size.zero;
    final elegida = await showMenu<AccionRapida>(
      context: context,
      position: RelativeRect.fromLTRB(
        posicion.dx,
        posicion.dy,
        pantalla.width - posicion.dx,
        pantalla.height - posicion.dy,
      ),
      items: [
        for (final accion in acciones)
          PopupMenuItem<AccionRapida>(
            value: accion,
            child: Row(
              children: [
                Icon(accion.icono, size: 18, color: accion.color),
                const SizedBox(width: 12),
                Text(accion.etiqueta, style: TextStyle(color: accion.color)),
              ],
            ),
          ),
      ],
    );
    elegida?.alPulsar();
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.colors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            for (final accion in acciones)
              ListTile(
                leading: Icon(
                  accion.icono,
                  color: accion.color ?? ctx.colors.accentSoft,
                ),
                title: Text(
                  accion.etiqueta,
                  style: TextStyle(color: accion.color),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  accion.alPulsar();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Abre el menú con una pulsación larga y, en escritorio, con el clic derecho.
class GestoMenuAcciones extends StatelessWidget {
  final Widget child;
  final List<AccionRapida> Function() acciones;

  /// A false, solo con el clic derecho. Es lo que hace falta donde la
  /// pulsación larga ya significa otra cosa, como seleccionar facturas.
  final bool conPulsacionLarga;

  const GestoMenuAcciones({
    super.key,
    required this.child,
    required this.acciones,
    this.conPulsacionLarga = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: !conPulsacionLarga
          ? null
          : (detalles) => mostrarMenuAcciones(
              context,
              acciones: acciones(),
              posicion: detalles.globalPosition,
            ),
      onSecondaryTapDown: (detalles) => mostrarMenuAcciones(
        context,
        acciones: acciones(),
        posicion: detalles.globalPosition,
      ),
      child: child,
    );
  }
}
