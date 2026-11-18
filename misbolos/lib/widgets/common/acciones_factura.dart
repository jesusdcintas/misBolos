import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/hapticos.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/sincronizar_bolo_calendario.dart';
import '../../models/client.dart';
import '../../models/gig.dart';
import '../../models/invoice.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/invoice_email_log_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tutorial_provider.dart';
import '../../services/notification_service.dart';
import '../../services/pdf_service.dart';
import 'menu_acciones.dart';
import 'serpentina_celebration.dart';

/// Comparte el PDF de una factura, generándolo como hace el detalle.
Future<void> compartirPdfDeFactura(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice,
) async {
  final caja = context.findRenderObject() as RenderBox?;
  final origen = caja != null
      ? caja.localToGlobal(Offset.zero) & caja.size
      : const Rect.fromLTWH(0, 0, 100, 100);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final client = await ref.read(clientByIdProvider(invoice.clientId).future);
    final settings = await ref.read(settingsProvider.future);
    if (client == null) return;

    final fichero = await PdfService().generateInvoicePdf(
      invoice: invoice,
      client: client,
      settings: settings,
    );
    // Paso de la guía: compartir cuenta en cuanto se abre la hoja del
    // sistema, se haga desde donde se haga y aunque luego se cancele.
    await ref.read(tutorialProvider.notifier).marcarFacturaCompartida();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(fichero.path)], sharePositionOrigin: origen),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
  }
}

/// Marca una factura como cobrada con aviso de «Deshacer».
///
/// Deshacer la devuelve a pendiente y el bolo a facturado, igual que hace la
/// acción de revertir en lote que ya existe.
Future<void> marcarCobradaConDeshacer(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice,
) async {
  if (invoice.status != InvoiceStatus.enviada) return;
  final messenger = ScaffoldMessenger.of(context);

  Future<void> aplicar(InvoiceStatus estado, GigStatus estadoBolo) async {
    await ref.read(invoicesProvider.notifier).updateStatus(invoice.id, estado);
    final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
    if (gig == null) return;
    await ref.read(gigsProvider.notifier).updateStatus(gig.id, estadoBolo);
    await sincronizarBoloEnCalendario(ref, gig.copyWith(status: estadoBolo));
  }

  Hapticos.umbral();
  await aplicar(InvoiceStatus.pagada, GigStatus.cobrado);
  // Cobrada: ya no hay que recordar nada, igual que al marcarlas en lote.
  await NotificationService.instance.cancelNotification(invoice.numero);
  Hapticos.exito();
  if (context.mounted) await showCobradoSerpentina(context);

  final cerrado = await messenger
      .showSnackBar(
        SnackBar(
          content: const Text('Factura marcada como cobrada'),
          duration: const Duration(seconds: 5),
          // Con acción, Flutter lo dejaría fijo: aquí debe cerrarse solo.
          persist: false,
          action: SnackBarAction(label: 'Deshacer', onPressed: () {}),
        ),
      )
      .closed;
  if (cerrado != SnackBarClosedReason.action) return;

  await aplicar(InvoiceStatus.enviada, GigStatus.facturado);
}

/// Envía la factura por correo al cliente, con su confirmación.
///
/// Es el mismo flujo que el botón del detalle: confirma, envía, deja el bolo
/// como facturado en el calendario y programa el recordatorio de cobro.
Future<void> enviarFacturaPorEmail(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final client = await ref.read(clientByIdProvider(invoice.clientId).future);
  if (client == null) return;
  if (client.email?.trim().isEmpty ?? true) {
    messenger.showSnackBar(
      const SnackBar(content: Text('El cliente no tiene email configurado')),
    );
    return;
  }

  if (!context.mounted) return;
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Enviar factura por email'),
      content: Text(
        'Se enviará la factura ${invoice.visualNumber} a ${client.email}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Enviar'),
        ),
      ],
    ),
  );
  if (confirmado != true) return;

  // Paso de la guía: enviar por correo también cuenta como compartir. Se
  // marca al confirmar el envío, aunque luego la red falle.
  await ref.read(tutorialProvider.notifier).marcarFacturaCompartida();

  try {
    await ref.read(invoiceEmailSendProvider.notifier).send(invoice);

    final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
    if (gig != null) {
      await sincronizarBoloEnCalendario(
        ref,
        gig.copyWith(status: GigStatus.facturado),
      );
    }

    final settings = await ref.read(settingsProvider.future);
    if (settings.notificacionesActivas) {
      await NotificationService.instance.schedulePaymentReminder(
        id: invoice.numero,
        clientName: client.displayName,
        total: invoice.total,
        invoiceNumber: invoice.numero,
        scheduledDate: DateTime.now().add(
          Duration(days: settings.diasRecordatorio),
        ),
      );
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Factura enviada a ${client.email}')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Error enviando email: $e')));
  }
}

/// Las acciones del menú rápido de una factura, ya listas para pintar.
///
/// Emitir, borrar y rectificar no están: son fiscales y viven en el detalle.
List<AccionRapida> accionesRapidasDeFactura(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice, {
  required bool puedeEnviarEmail,
}) {
  final colors = context.colors;
  return [
    for (final accion in accionesDeFactura(
      invoice,
      puedeEnviarEmail: puedeEnviarEmail,
    ))
      switch (accion) {
        AccionFactura.ver => AccionRapida(
          icono: Icons.visibility_outlined,
          etiqueta: 'Ver factura',
          alPulsar: () => context.push('/invoice/${invoice.id}'),
        ),
        AccionFactura.compartirPdf => AccionRapida(
          icono: Icons.share_outlined,
          etiqueta: 'Compartir PDF',
          alPulsar: () => compartirPdfDeFactura(context, ref, invoice),
        ),
        AccionFactura.enviarEmail => AccionRapida(
          icono: Icons.mail_outline,
          etiqueta: 'Enviar por correo',
          alPulsar: () => enviarFacturaPorEmail(context, ref, invoice),
        ),
        AccionFactura.marcarCobrada => AccionRapida(
          icono: Icons.check_circle_outline,
          etiqueta: 'Marcar como cobrada',
          color: colors.success,
          alPulsar: () => marcarCobradaConDeshacer(context, ref, invoice),
        ),
      },
  ];
}
