import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/hapticos.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/sincronizar_bolo_calendario.dart';
import '../../models/franja_bolo.dart';
import '../../models/gig.dart';
import '../../providers/gig_provider.dart';
import 'menu_acciones.dart';

/// Ruta para duplicar un bolo: mismo cliente, caché, franja y facturable, con
/// la fecha de hoy. No se copia nada ligado a la factura ni al estado.
String rutaDuplicarBolo(Gig gig) {
  final parametros = <String, String>{
    'fecha': DateFormatter.isoDay(DateTime.now()),
    if (gig.clientId.isNotEmpty) 'cliente': gig.clientId,
    if (gig.cachet != null) 'cachet': gig.cachet!.toString(),
    if (gig.franja != null) 'franja': gig.franja!.dbValue,
    'facturable': gig.facturable ? '1' : '0',
  };
  final consulta = parametros.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return '/gig/new?$consulta';
}

/// Las acciones del menú rápido de un bolo, ya listas para pintar.
List<AccionRapida> accionesRapidasDeBolo(
  BuildContext context,
  WidgetRef ref,
  Gig gig, {
  required Future<void> Function(Gig gig) alCancelar,
}) {
  final colors = context.colors;
  return [
    for (final accion in accionesDeBolo(gig))
      switch (accion) {
        AccionBolo.ver => AccionRapida(
          icono: Icons.visibility_outlined,
          etiqueta: 'Ver bolo',
          alPulsar: () => context.push('/gig/${gig.id}'),
        ),
        AccionBolo.editar => AccionRapida(
          icono: Icons.edit_outlined,
          etiqueta: 'Editar bolo',
          alPulsar: () => context.push('/gig/edit/${gig.id}'),
        ),
        AccionBolo.duplicar => AccionRapida(
          icono: Icons.copy_outlined,
          etiqueta: 'Duplicar bolo',
          alPulsar: () => context.push(rutaDuplicarBolo(gig)),
        ),
        AccionBolo.facturar => AccionRapida(
          icono: Icons.receipt_long_outlined,
          etiqueta: 'Generar factura',
          color: colors.success,
          alPulsar: () => context.push('/invoice/new/${gig.id}'),
        ),
        AccionBolo.verFactura => AccionRapida(
          icono: Icons.receipt_outlined,
          etiqueta: 'Ver factura',
          color: colors.success,
          alPulsar: () => context.push('/invoice/${gig.invoiceId}'),
        ),
        AccionBolo.cancelar => AccionRapida(
          icono: Icons.cancel_outlined,
          etiqueta: 'Cancelar bolo',
          color: colors.warning,
          alPulsar: () => alCancelar(gig),
        ),
      },
  ];
}

/// Cancela un bolo con aviso de «Deshacer», sin preguntar antes.
///
/// Vuelve al estado que tenía, que es lo que hace reversible la acción.
Future<void> cancelarBoloConDeshacer(
  BuildContext context,
  WidgetRef ref,
  Gig gig,
) async {
  final estadoAnterior = gig.status;
  final messenger = ScaffoldMessenger.of(context);

  Hapticos.umbral();
  await ref
      .read(gigsProvider.notifier)
      .updateStatus(gig.id, GigStatus.cancelado);
  await sincronizarBoloEnCalendario(
    ref,
    gig.copyWith(status: GigStatus.cancelado),
  );
  ref.invalidate(gigByIdProvider(gig.id));

  final cerrado = await messenger
      .showSnackBar(
        SnackBar(
          content: const Text('Bolo cancelado'),
          duration: const Duration(seconds: 5),
          // Con acción, Flutter lo dejaría fijo: aquí debe cerrarse solo.
          persist: false,
          action: SnackBarAction(label: 'Deshacer', onPressed: () {}),
        ),
      )
      .closed;
  if (cerrado != SnackBarClosedReason.action) return;

  await ref.read(gigsProvider.notifier).updateStatus(gig.id, estadoAnterior);
  await sincronizarBoloEnCalendario(ref, gig.copyWith(status: estadoAnterior));
  ref.invalidate(gigByIdProvider(gig.id));
}
