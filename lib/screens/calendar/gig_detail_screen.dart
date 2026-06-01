import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/facturable_badge.dart';
import '../../widgets/common/cobrado_confetti_button.dart';

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
          Hero(
            tag: 'gig-${gig.id}',
            child: Card(
              child: ListTile(
                leading: const Icon(
                  Icons.calendar_today,
                  color: AppColors.primary,
                ),
                title: const Text(AppStrings.fecha),
                subtitle: Text(DateFormatter.dayOfWeek(gig.fecha)),
              ),
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
              StatusBadge(
                status: gig.status,
                facturable: gig.facturable,
                large: true,
              ),
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
        case GigStatus.confirmado:
          actions.add(
            _ActionButton(
              label: AppStrings.generarFactura,
              icon: Icons.receipt_long,
              color: AppColors.primary,
              onPressed: () => _generateInvoice(context, ref, gig),
            ),
          );
          break;
        case GigStatus.facturado:
          actions.addAll([
            _ActionButton(
              label: 'Ver factura',
              icon: Icons.picture_as_pdf,
              color: AppColors.primary,
              onPressed: () => _viewPdf(context, ref, gig),
            ),
          ]);
          break;
        case GigStatus.cobrado:
          actions.add(
            _ActionButton(
              label: 'Ver factura',
              icon: Icons.picture_as_pdf,
              color: AppColors.primary,
              onPressed: () => _viewPdf(context, ref, gig),
            ),
          );
          break;
        default:
          break;
      }
    } else {
      // No facturable
      if (gig.status == GigStatus.confirmadoB) {
        actions.add(
          _ActionButton(
            label: 'Marcar realizado privado',
            icon: Icons.task_alt,
            color: AppColors.purple,
            onPressed: () => _markAsRealizadoEnB(context, ref, gig),
          ),
        );
      } else if (gig.status == GigStatus.realizadoB) {
        actions.add(
          CobradoConfettiButton(
            label: AppStrings.marcarCobradoEnB,
            icon: Icons.money_off,
            color: AppColors.accentPurple,
            onPressed: () => _markAsCobradoEnB(context, ref, gig),
          ),
        );
      }
    }

    if (gig.status != GigStatus.cancelado &&
        gig.status != GigStatus.cobrado &&
        gig.status != GigStatus.cobradoB) {
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
    BuildContext context,
    WidgetRef ref,
    Gig gig,
  ) async {
    // Navegar al formulario de factura
    context.push('/invoice/new/${gig.id}');
  }

  Future<void> _viewPdf(BuildContext context, WidgetRef ref, Gig gig) async {
    debugPrint(
      '[GigDetail] pdf invoice lookup gig_id=${gig.id} invoice_id=${gig.invoiceId}',
    );
    Invoice? invoice;
    if (gig.invoiceId != null) {
      invoice = await ref.read(invoiceByIdProvider(gig.invoiceId!).future);
    }
    invoice ??= await ref.read(invoiceByGigProvider(gig.id).future);
    if (!context.mounted) return;
    if (invoice == null) {
      await ref
          .read(invoicesProvider.notifier)
          .refreshFromCloud(reason: 'pdf_invoice_lookup_missing', force: true);
      invoice = await ref.read(invoiceByGigProvider(gig.id).future);
    }
    if (!context.mounted) return;
    if (invoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Factura no encontrada. Sincroniza e inténtalo de nuevo.',
          ),
        ),
      );
      return;
    }
    debugPrint(
      '[GigDetail] pdf invoice lookup done invoice_id=${invoice.id} gig_id=${invoice.gigId}',
    );
    context.push('/invoice/${invoice.id}');
  }

  Future<void> _markAsCobradoEnB(
    BuildContext context,
    WidgetRef ref,
    Gig gig,
  ) async {
    HapticFeedback.heavyImpact();
    await ref
        .read(gigsProvider.notifier)
        .updateStatus(gig.id, GigStatus.cobradoB);
    ref.invalidate(gigByIdProvider(gig.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marcado como cobrado privado')),
      );
    }
  }

  Future<void> _markAsRealizadoEnB(
    BuildContext context,
    WidgetRef ref,
    Gig gig,
  ) async {
    HapticFeedback.mediumImpact();
    await ref
        .read(gigsProvider.notifier)
        .updateStatus(gig.id, GigStatus.realizadoB);
    ref.invalidate(gigByIdProvider(gig.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marcado como realizado privado')),
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

  Future<void> _cancelGig(BuildContext context, WidgetRef ref, Gig gig) async {
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
            child: Text(
              AppStrings.cancelarBolo,
              style: const TextStyle(color: AppColors.accentRed),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.heavyImpact();
      await ref
          .read(gigsProvider.notifier)
          .updateStatus(gig.id, GigStatus.cancelado);

      // Sync cancellation to Google Calendar
      final updatedGig = gig.copyWith(status: GigStatus.cancelado);
      await _syncGigToCalendar(ref, updatedGig);

      ref.invalidate(gigByIdProvider(gig.id));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bolo cancelado')));
      }
    }
  }

  Future<void> _deleteGig(BuildContext context, WidgetRef ref, Gig gig) async {
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
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.error),
            ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bolo eliminado')));
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
