import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/invoice.dart';
import '../../models/invoice_email_log.dart';
import '../../models/gig.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/invoice_email_log_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/notification_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import 'package:share_plus/share_plus.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(invoiceId));

    return invoiceAsync.when(
      data: (invoice) {
        if (invoice == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Factura no encontrada')),
          );
        }
        return _InvoiceDetailContent(invoiceId: invoiceId, invoice: invoice);
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _InvoiceDetailContent extends ConsumerWidget {
  final String invoiceId;
  final Invoice invoice;
  const _InvoiceDetailContent({required this.invoiceId, required this.invoice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(invoice.clientId));
    final settingsAsync = ref.watch(settingsProvider);
    final emailSendState = ref.watch(invoiceEmailSendProvider);
    final emailLogsAsync = ref.watch(invoiceEmailLogsProvider(invoice.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Factura #${invoice.numero}'),
        actions: [
          if (invoice.status == InvoiceStatus.borrador)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => context.push('/invoice/edit/${invoice.id}'),
            ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _share(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preview card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FACTURA',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        '#${invoice.numero}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Emisor / Cliente
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.emisor,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            settingsAsync.when(
                              data: (s) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.emisorNombre,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (s.emisorNIF.isNotEmpty)
                                    Text(
                                      s.emisorNIF,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (s.emisorDireccion.isNotEmpty)
                                    Text(
                                      s.emisorDireccion,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (s.emisorCiudad.isNotEmpty ||
                                      s.emisorProvincia.isNotEmpty ||
                                      s.emisorCodigoPostal.isNotEmpty)
                                    Text(
                                      [
                                            s.emisorCiudad,
                                            if (s.emisorProvincia.isNotEmpty)
                                              s.emisorProvincia,
                                            if (s.emisorCodigoPostal.isNotEmpty)
                                              s.emisorCodigoPostal,
                                          ]
                                          .where((str) => str.isNotEmpty)
                                          .join(', '),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (s.emisorEmail.isNotEmpty)
                                    Text(
                                      s.emisorEmail,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  if (s.emisorTelefono.isNotEmpty)
                                    Text(
                                      s.emisorTelefono,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                              loading: () => const SizedBox(),
                              error: (_, __) => const SizedBox(),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.facturarA,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            clientAsync.when(
                              data: (c) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c?.nombre ?? '',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (c?.cifNif.isNotEmpty == true)
                                    Text(
                                      c!.cifNif,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (c?.direccion.isNotEmpty == true)
                                    Text(
                                      c!.direccion,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (c?.ciudad.isNotEmpty == true ||
                                      c?.codigoPostal.isNotEmpty == true ||
                                      c?.provincia.isNotEmpty == true)
                                    Text(
                                      [
                                        c?.ciudad ?? '',
                                        if (c?.provincia.isNotEmpty == true)
                                          c!.provincia,
                                        if (c?.codigoPostal.isNotEmpty == true)
                                          c!.codigoPostal,
                                      ].where((s) => s.isNotEmpty).join(', '),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (c?.email != null && c!.email!.isNotEmpty)
                                    Text(
                                      c.email!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  if (c?.telefono != null &&
                                      c!.telefono!.isNotEmpty)
                                    Text(
                                      c.telefono!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                              loading: () => const SizedBox(),
                              error: (_, __) => const SizedBox(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'Fecha: ${DateFormatter.display(invoice.fecha)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // Items table
                  Table(
                    border: TableBorder.all(color: AppColors.divider),
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(3),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: AppColors.primary),
                        children: [
                          _tableHeader(AppStrings.cantidad),
                          _tableHeader(AppStrings.descripcion),
                          _tableHeader(AppStrings.precioUnidad),
                          _tableHeader(AppStrings.totalLinea),
                        ],
                      ),
                      for (final item in invoice.items)
                        TableRow(
                          children: [
                            _tableCell('${item.cantidad}', TextAlign.center),
                            _tableCell(item.descripcion, TextAlign.left),
                            _tableCell(
                              CurrencyFormatter.format(item.precioUnitario),
                              TextAlign.right,
                            ),
                            _tableCell(
                              CurrencyFormatter.format(item.totalLinea),
                              TextAlign.right,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Totals
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Subtotal: ${CurrencyFormatter.format(invoice.subtotal)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          'IVA (${(invoice.ivaRate * 100).toStringAsFixed(0)}%): ${CurrencyFormatter.format(invoice.ivaAmount)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (invoice.irpfRate > 0)
                          Text(
                            'Retención IRPF (${(invoice.irpfRate * 100).toStringAsFixed(0)}%): -${CurrencyFormatter.format(invoice.irpfAmount)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.accentRed,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'TOTAL: ${CurrencyFormatter.format(invoice.total)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Estado
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: _statusBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                invoice.status.label,
                style: TextStyle(
                  color: _statusTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Cambiar estado
          if (invoice.status == InvoiceStatus.borrador)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _markAs(context, ref, InvoiceStatus.enviada),
                icon: const Icon(Icons.send),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                ),
                label: const Text('Marcar como pendiente'),
              ),
            ),
          if (invoice.status == InvoiceStatus.enviada)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _markAs(context, ref, InvoiceStatus.pagada),
                icon: const Icon(Icons.check_circle),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                label: const Text('Marcar como cobrada'),
              ),
            ),
          if (invoice.status != InvoiceStatus.borrador) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _revertStatus(context, ref),
                icon: const Icon(Icons.undo),
                label: Text(
                  invoice.status == InvoiceStatus.pagada
                      ? 'Revertir a pendiente'
                      : 'Revertir a borrador',
                ),
              ),
            ),
          ],
          if (invoice.status != InvoiceStatus.pagada) const SizedBox(height: 8),

          // Editar (solo en borrador)
          if (invoice.status == InvoiceStatus.borrador)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/invoice/edit/${invoice.id}'),
                icon: const Icon(Icons.edit),
                label: const Text('Editar factura'),
              ),
            ),
          if (invoice.status == InvoiceStatus.borrador)
            const SizedBox(height: 8),

          // Compartir
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _share(context, ref),
              icon: const Icon(Icons.share),
              label: const Text(AppStrings.compartirPDF),
            ),
          ),
          const SizedBox(height: 8),

          // Enviar por email
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: emailSendState.isLoading
                  ? null
                  : () => _sendByEmail(context, ref),
              icon: emailSendState.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_read_outlined),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              label: const Text('Enviar por email'),
            ),
          ),
          const SizedBox(height: 16),

          emailLogsAsync.when(
            data: (logs) => _EmailLogSection(logs: logs),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),

          // Cambiar número de factura
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _changeNumber(context, ref),
              icon: const Icon(Icons.numbers),
              label: const Text('Cambiar número de factura'),
            ),
          ),
          const SizedBox(height: 8),

          // Eliminar factura
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deleteInvoice(context, ref),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              label: const Text('Eliminar factura'),
            ),
          ),
        ],
      ),
    );
  }

  Color get _statusBgColor {
    switch (invoice.status) {
      case InvoiceStatus.borrador:
        return AppColors.primaryLight;
      case InvoiceStatus.enviada:
        return AppColors.warningBg;
      case InvoiceStatus.pagada:
        return AppColors.successBg;
    }
  }

  Color get _statusTextColor {
    switch (invoice.status) {
      case InvoiceStatus.borrador:
        return AppColors.primary;
      case InvoiceStatus.enviada:
        return AppColors.warning;
      case InvoiceStatus.pagada:
        return AppColors.success;
    }
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _tableCell(String text, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: const TextStyle(fontSize: 11), textAlign: align),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    try {
      final client = await ref.read(
        clientByIdProvider(invoice.clientId).future,
      );
      final settings = await ref.read(settingsProvider.future);

      if (client == null) return;

      final file = await PdfService().generateInvoicePdf(
        invoice: invoice,
        client: client,
        settings: settings,
      );

      await Share.shareXFiles([
        XFile(file.path),
      ], sharePositionOrigin: shareOrigin);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _sendByEmail(BuildContext context, WidgetRef ref) async {
    final client = await ref.read(clientByIdProvider(invoice.clientId).future);
    if (client == null) return;
    if (!context.mounted) return;
    if (client.email == null || client.email!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente no tiene email configurado')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar factura por email'),
        content: Text(
          'Se enviará la factura #${invoice.numero} a ${client.email}.',
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
    if (confirm != true || !context.mounted) return;

    try {
      await ref.read(invoiceEmailSendProvider.notifier).send(invoice);

      final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
      if (!context.mounted) return;
      if (gig != null) {
        final newGig = gig.copyWith(status: GigStatus.facturaEnviada);
        await _syncGigToCalendar(context, ref, newGig);
      }

      final settings = await ref.read(settingsProvider.future);
      if (settings.notificacionesActivas) {
        await NotificationService.instance.schedulePaymentReminder(
          id: invoice.numero,
          clientName: client.nombre,
          total: invoice.total,
          invoiceNumber: invoice.numero,
          scheduledDate: DateTime.now().add(
            Duration(days: settings.diasRecordatorio),
          ),
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Factura enviada a ${client.email}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error enviando email: $e')));
      }
    }
  }

  Future<void> _changeNumber(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: invoice.numero.toString());

    final newNumber = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar número de factura'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nuevo número',
                hintText: 'Ej: 1, 2, 3...',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              'Asegúrate de que el número no esté en uso por otra factura.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final num = int.tryParse(controller.text.trim());
              if (num != null && num > 0) {
                Navigator.pop(ctx, num);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newNumber != null && newNumber != invoice.numero && context.mounted) {
      // Verificar si el número ya está en uso
      final isTaken = await ref
          .read(invoicesProvider.notifier)
          .isNumberTaken(newNumber, excludeId: invoice.id);

      if (isTaken) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'El número $newNumber ya está en uso por otra factura',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await ref
          .read(invoicesProvider.notifier)
          .updateNumber(invoice.id, newNumber);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Número de factura cambiado a #$newNumber')),
        );
        // Volver a la lista para ver el cambio
        context.pop();
      }
    }
  }

  Future<void> _markAs(
    BuildContext context,
    WidgetRef ref,
    InvoiceStatus status,
  ) async {
    final statusLabel = status == InvoiceStatus.enviada ? 'enviada' : 'pagada';

    // Actualizar factura
    await ref.read(invoicesProvider.notifier).updateStatus(invoice.id, status);

    // Actualizar gig asociado
    final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
    if (gig != null) {
      GigStatus newGigStatus;
      if (status == InvoiceStatus.enviada) {
        newGigStatus = GigStatus.facturaEnviada;
        // Programar recordatorio
        final settings = await ref.read(settingsProvider.future);
        if (settings.notificacionesActivas) {
          final client = await ref.read(
            clientByIdProvider(invoice.clientId).future,
          );
          if (client != null) {
            await NotificationService.instance.schedulePaymentReminder(
              id: invoice.numero,
              clientName: client.nombre,
              total: invoice.total,
              invoiceNumber: invoice.numero,
              scheduledDate: DateTime.now().add(
                Duration(days: settings.diasRecordatorio),
              ),
            );
          }
        }
      } else {
        newGigStatus = GigStatus.pagado;
        // Cancelar recordatorio
        await NotificationService.instance.cancelNotification(invoice.numero);
      }

      await ref.read(gigsProvider.notifier).updateStatus(gig.id, newGigStatus);

      // Sincronizar con Google Calendar
      if (!context.mounted) return;
      await _syncGigToCalendar(
        context,
        ref,
        gig.copyWith(status: newGigStatus),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura marcada como $statusLabel')),
      );
    }
  }

  Future<void> _revertStatus(BuildContext context, WidgetRef ref) async {
    InvoiceStatus newStatus;
    GigStatus newGigStatus;
    String statusLabel;

    if (invoice.status == InvoiceStatus.pagada) {
      newStatus = InvoiceStatus.enviada;
      newGigStatus = GigStatus.facturaEnviada;
      statusLabel = 'enviada';
    } else {
      newStatus = InvoiceStatus.borrador;
      newGigStatus = GigStatus.facturaGenerada;
      statusLabel = 'borrador';
    }

    // Actualizar factura
    await ref
        .read(invoicesProvider.notifier)
        .updateStatus(invoice.id, newStatus);

    // Actualizar gig asociado
    final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
    if (gig != null) {
      await ref.read(gigsProvider.notifier).updateStatus(gig.id, newGigStatus);
      if (!context.mounted) return;
      await _syncGigToCalendar(
        context,
        ref,
        gig.copyWith(status: newGigStatus),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Factura revertida a $statusLabel')),
      );
    }
  }

  Future<void> _syncGigToCalendar(
    BuildContext context,
    WidgetRef ref,
    Gig gig,
  ) async {
    if (!context.mounted) return;
    final authState = ref.read(googleAuthProvider);
    if (!authState.isSignedIn) return;
    try {
      if (!context.mounted) return;
      final client = await ref.read(clientByIdProvider(gig.clientId).future);
      await GoogleCalendarService().syncGig(
        gig: gig,
        clientName: client?.nombre ?? 'Cliente',
        cachet: gig.cachet,
      );
    } catch (_) {}
  }

  Future<void> _deleteInvoice(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar factura?'),
        content: Text(
          'Se eliminará permanentemente la factura #${invoice.numero}. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await ref.read(invoicesProvider.notifier).remove(invoice.id);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Factura eliminada')));
        context.pop();
      }
    }
  }
}

class _EmailLogSection extends StatelessWidget {
  final List<InvoiceEmailLog> logs;

  const _EmailLogSection({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return const SizedBox.shrink();
    final latest = logs.first;
    final color = switch (latest.status) {
      InvoiceEmailStatus.sent => AppColors.success,
      InvoiceEmailStatus.failed => AppColors.error,
      InvoiceEmailStatus.pending => AppColors.warning,
    };
    final label = switch (latest.status) {
      InvoiceEmailStatus.sent => 'Enviada por email',
      InvoiceEmailStatus.failed => 'Email fallido',
      InvoiceEmailStatus.pending => 'Email pendiente',
    };

    return Card(
      child: ListTile(
        leading: Icon(Icons.email_outlined, color: color),
        title: Text(label),
        subtitle: Text(
          latest.status == InvoiceEmailStatus.failed &&
                  latest.errorMessage != null
              ? latest.errorMessage!
              : latest.recipientEmail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${logs.length}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
