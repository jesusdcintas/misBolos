import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/gig.dart';
import '../../models/invoice.dart';
import '../../providers/gig_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/notification_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import '../../services/google_drive_service.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/facturable_badge.dart';
import 'package:share_plus/share_plus.dart';

class GigDetailScreen extends ConsumerWidget {
  final String gigId;
  const GigDetailScreen({super.key, required this.gigId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gigAsync = ref.watch(gigByIdProvider(gigId));

    return gigAsync.when(
      data: (gig) {
        if (gig == null) {
          return Scaffold(
            appBar: AppBar(title: const Text(AppStrings.detalleBolo)),
            body: const Center(child: Text('Bolo no encontrado')),
          );
        }
        return _GigDetailContent(gig: gig);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text(AppStrings.detalleBolo)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text(AppStrings.detalleBolo)),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _GigDetailContent extends ConsumerWidget {
  final Gig gig;
  const _GigDetailContent({required this.gig});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(gig.clientId));
    final invoiceAsync = gig.invoiceId != null
        ? ref.watch(invoiceByIdProvider(gig.invoiceId!))
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.detalleBolo),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/gig/edit/${gig.id}'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Fecha
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: AppColors.primary),
              title: const Text(AppStrings.fecha),
              subtitle: Text(DateFormatter.dayOfWeek(gig.fecha)),
            ),
          ),

          // Cliente
          Card(
            child: clientAsync.when(
              data: (client) => ListTile(
                leading: const Icon(Icons.person, color: AppColors.primary),
                title: const Text(AppStrings.cliente),
                subtitle: Text(client?.nombre ?? 'Desconocido'),
                onTap: client != null
                    ? () => context.push('/client/${client.id}')
                    : null,
              ),
              loading: () => const ListTile(title: Text('Cargando...')),
              error: (_, __) => const ListTile(title: Text('Error')),
            ),
          ),

          // Caché
          if (gig.cachet != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.euro, color: AppColors.primary),
                title: const Text(AppStrings.cachet),
                subtitle: Text(CurrencyFormatter.format(gig.cachet!)),
              ),
            ),

          // Notas
          if (gig.notas != null && gig.notas!.isNotEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.notes, color: AppColors.primary),
                title: const Text(AppStrings.notas),
                subtitle: Text(gig.notas!),
              ),
            ),

          const SizedBox(height: 16),

          // Badge estado y facturable
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FacturableBadge(facturable: gig.facturable, large: true),
              const SizedBox(width: 12),
              StatusBadge(status: gig.status, large: true),
            ],
          ),

          const SizedBox(height: 24),

          // Acciones según estado
          ..._buildActions(context, ref, gig, invoiceAsync),
        ],
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    Gig gig,
    AsyncValue<Invoice?>? invoiceAsync,
  ) {
    final actions = <Widget>[];

    if (gig.facturable) {
      switch (gig.status) {
        case GigStatus.pendiente:
          actions.add(_ActionButton(
            label: AppStrings.generarFactura,
            icon: Icons.receipt_long,
            color: AppColors.primary,
            onPressed: () => _generateInvoice(context, ref, gig),
          ));
          break;
        case GigStatus.facturaGenerada:
          actions.addAll([
            _ActionButton(
              label: AppStrings.verPDF,
              icon: Icons.picture_as_pdf,
              color: AppColors.primary,
              onPressed: () => _viewPdf(context, ref, gig),
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: AppStrings.marcarEnviada,
              icon: Icons.send,
              color: AppColors.accentOrange,
              onPressed: () => _markAsSent(context, ref, gig),
            ),
          ]);
          break;
        case GigStatus.facturaEnviada:
          actions.addAll([
            _ActionButton(
              label: AppStrings.verPDF,
              icon: Icons.picture_as_pdf,
              color: AppColors.primary,
              onPressed: () => _viewPdf(context, ref, gig),
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: AppStrings.compartirPDF,
              icon: Icons.share,
              color: AppColors.primary,
              onPressed: () => _sharePdf(context, ref, gig),
            ),
            const SizedBox(height: 8),
            if (ref.read(googleAuthProvider).isSignedIn)
              _ActionButton(
                label: 'Subir a Google Drive',
                icon: Icons.cloud_upload,
                color: AppColors.primary,
                onPressed: () => _uploadPdfToDrive(context, ref, gig),
              ),
            if (ref.read(googleAuthProvider).isSignedIn)
              const SizedBox(height: 8),
            _ActionButton(
              label: AppStrings.marcarPagado,
              icon: Icons.check_circle,
              color: AppColors.accentGreen,
              onPressed: () => _markAsPaid(context, ref, gig),
            ),
          ]);
          break;
        case GigStatus.pagado:
          actions.add(_ActionButton(
            label: AppStrings.verPDF,
            icon: Icons.picture_as_pdf,
            color: AppColors.primary,
            onPressed: () => _viewPdf(context, ref, gig),
          ));
          break;
        default:
          break;
      }
    } else {
      // No facturable
      if (gig.status == GigStatus.pendiente) {
        actions.add(_ActionButton(
          label: AppStrings.marcarCobradoEnB,
          icon: Icons.money_off,
          color: AppColors.accentPurple,
          onPressed: () => _markAsCobradoEnB(context, ref, gig),
        ));
      }
    }

    if (gig.status != GigStatus.cancelado &&
        gig.status != GigStatus.pagado &&
        gig.status != GigStatus.cobradoEnB) {
      actions.addAll([
        const SizedBox(height: 16),
        _ActionButton(
          label: AppStrings.cancelarBolo,
          icon: Icons.cancel,
          color: AppColors.accentRed,
          onPressed: () => _cancelGig(context, ref, gig),
          outlined: true,
        ),
      ]);
    }

    // Siempre mostrar opción de eliminar
    actions.addAll([
      const SizedBox(height: 8),
      _ActionButton(
        label: 'Eliminar bolo',
        icon: Icons.delete_forever,
        color: AppColors.error,
        onPressed: () => _deleteGig(context, ref, gig),
        outlined: true,
      ),
    ]);

    return actions;
  }

  Future<void> _generateInvoice(
      BuildContext context, WidgetRef ref, Gig gig) async {
    // Navegar al formulario de factura
    context.push('/invoice/new/${gig.id}');
  }

  Future<void> _viewPdf(BuildContext context, WidgetRef ref, Gig gig) async {
    if (gig.invoiceId == null) return;
    context.push('/invoice/${gig.invoiceId}');
  }

  Future<void> _sharePdf(BuildContext context, WidgetRef ref, Gig gig) async {
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    try {
      if (gig.invoiceId == null) return;
      final invoice = await ref.read(invoiceByIdProvider(gig.invoiceId!).future);
      final client = await ref.read(clientByIdProvider(gig.clientId).future);
      final settings = await ref.read(settingsProvider.future);

      if (invoice == null || client == null) return;

      final file = await PdfService().generateInvoicePdf(
        invoice: invoice,
        client: client,
        settings: settings,
      );

      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _markAsSent(BuildContext context, WidgetRef ref, Gig gig) async {
    await ref
        .read(gigsProvider.notifier)
        .updateStatus(gig.id, GigStatus.facturaEnviada);
    if (gig.invoiceId != null) {
      await ref
          .read(invoicesProvider.notifier)
          .updateStatus(gig.invoiceId!, InvoiceStatus.enviada);
    }

    // Programar recordatorio
    final settings = await ref.read(settingsProvider.future);
    if (settings.notificacionesActivas) {
      final client = await ref.read(clientByIdProvider(gig.clientId).future);
      final invoice = gig.invoiceId != null
          ? await ref.read(invoiceByIdProvider(gig.invoiceId!).future)
          : null;
      if (client != null && invoice != null) {
        await NotificationService.instance.schedulePaymentReminder(
          id: invoice.numero,
          clientName: client.nombre,
          total: invoice.total,
          invoiceNumber: invoice.numero,
          scheduledDate:
              DateTime.now().add(Duration(days: settings.diasRecordatorio)),
        );
      }
    }

    // Sync status to Google Calendar
    final updatedGig = gig.copyWith(status: GigStatus.facturaEnviada);
    await _syncGigToCalendar(ref, updatedGig);

    ref.invalidate(gigByIdProvider(gig.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura marcada como enviada')),
      );
    }
  }

  Future<void> _markAsPaid(BuildContext context, WidgetRef ref, Gig gig) async {
    await ref
        .read(gigsProvider.notifier)
        .updateStatus(gig.id, GigStatus.pagado);
    if (gig.invoiceId != null) {
      await ref
          .read(invoicesProvider.notifier)
          .updateStatus(gig.invoiceId!, InvoiceStatus.pagada);

      final invoice = await ref.read(invoiceByIdProvider(gig.invoiceId!).future);
      if (invoice != null) {
        await NotificationService.instance.cancelNotification(invoice.numero);
      }
    }
    // Sync status to Google Calendar
    final updatedGig = gig.copyWith(status: GigStatus.pagado);
    await _syncGigToCalendar(ref, updatedGig);

    ref.invalidate(gigByIdProvider(gig.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bolo marcado como pagado')),
      );
    }
  }

  Future<void> _markAsCobradoEnB(
      BuildContext context, WidgetRef ref, Gig gig) async {
    await ref
        .read(gigsProvider.notifier)
        .updateStatus(gig.id, GigStatus.cobradoEnB);
    ref.invalidate(gigByIdProvider(gig.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marcado como cobrado en B')),
      );
    }
  }

  Future<void> _syncGigToCalendar(WidgetRef ref, Gig gig) async {
    final authState = ref.read(googleAuthProvider);
    if (!authState.isSignedIn) return;
    try {
      final client = await ref.read(clientByIdProvider(gig.clientId).future);
      await GoogleCalendarService().syncGig(
        gig: gig,
        clientName: client?.nombre ?? 'Cliente',
        cachet: gig.cachet,
      );
    } catch (_) {}
  }

  Future<void> _uploadPdfToDrive(BuildContext context, WidgetRef ref, Gig gig) async {
    final authState = ref.read(googleAuthProvider);
    if (!authState.isSignedIn) return;
    try {
      if (gig.invoiceId == null) return;
      final invoice = await ref.read(invoiceByIdProvider(gig.invoiceId!).future);
      final client = await ref.read(clientByIdProvider(gig.clientId).future);
      final settings = await ref.read(settingsProvider.future);
      if (invoice == null || client == null) return;

      final file = await PdfService().generateInvoicePdf(
        invoice: invoice,
        client: client,
        settings: settings,
      );

      await GoogleDriveService().uploadInvoicePdf(
        file,
        'Factura_${invoice.numero}_${client.nombre}',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Factura subida a Google Drive')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error subiendo a Drive: $e')),
        );
      }
    }
  }

  Future<void> _cancelGig(
      BuildContext context, WidgetRef ref, Gig gig) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar bolo?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancelar),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppStrings.cancelarBolo,
                style: const TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref
          .read(gigsProvider.notifier)
          .updateStatus(gig.id, GigStatus.cancelado);

      // Sync cancellation to Google Calendar
      final updatedGig = gig.copyWith(status: GigStatus.cancelado);
      await _syncGigToCalendar(ref, updatedGig);

      ref.invalidate(gigByIdProvider(gig.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bolo cancelado')),
        );
      }
    }
  }

  Future<void> _deleteGig(
      BuildContext context, WidgetRef ref, Gig gig) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar bolo?'),
        content: const Text(
          'Esta acción eliminará el bolo permanentemente y no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancelar),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Eliminar de Google Calendar si está sincronizado
      final googleAuth = ref.read(googleAuthProvider);
      if (googleAuth.isSignedIn) {
        try {
          await GoogleCalendarService().deleteGig(gig.id);
        } catch (_) {
          // Ignorar error si no existe en Google Calendar
        }
      }

      await ref.read(gigsProvider.notifier).remove(gig.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bolo eliminado')),
        );
        context.pop();
      }
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool outlined;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, color: color),
          label: Text(label, style: TextStyle(color: color)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: color),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
