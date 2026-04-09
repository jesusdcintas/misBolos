import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/invoice.dart';
import '../../models/gig.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/notification_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../models/client.dart';

final _filterProvider = StateProvider<InvoiceStatus?>((ref) => null);

enum InvoiceSortOption { fechaDesc, fechaAsc, clienteAsc, clienteDesc, precioDesc, precioAsc }
final _sortProvider = StateProvider<InvoiceSortOption>((ref) => InvoiceSortOption.fechaDesc);

// Modo selección masiva
final _selectionModeProvider = StateProvider<bool>((ref) => false);
final _selectedInvoicesProvider = StateProvider<Set<String>>((ref) => {});

// Cache para nombres de clientes en ordenación
final _clientsCacheProvider = FutureProvider<Map<String, Client>>((ref) async {
  final clients = await ref.watch(clientsProvider.future);
  return {for (var c in clients) c.id: c};
});

class InvoicesListScreen extends ConsumerWidget {
  const InvoicesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);
    final filter = ref.watch(_filterProvider);
    final sortOption = ref.watch(_sortProvider);
    final clientsCacheAsync = ref.watch(_clientsCacheProvider);
    final selectionMode = ref.watch(_selectionModeProvider);
    final selectedInvoices = ref.watch(_selectedInvoicesProvider);

    return Scaffold(
      appBar: selectionMode
          ? _buildSelectionAppBar(context, ref, selectedInvoices)
          : AppBar(
              title: const Text(AppStrings.facturas),
              actions: [
                // Botón de selección masiva
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: 'Selección masiva',
                  onPressed: () {
                    ref.read(_selectionModeProvider.notifier).state = true;
                  },
                ),
                // Botón de ordenación
                PopupMenuButton<InvoiceSortOption>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Ordenar',
                  onSelected: (value) {
                    ref.read(_sortProvider.notifier).state = value;
                  },
                  itemBuilder: (context) => [
                    _buildSortMenuItem(context, sortOption, InvoiceSortOption.fechaDesc, 'Fecha (reciente)', Icons.arrow_downward),
                    _buildSortMenuItem(context, sortOption, InvoiceSortOption.fechaAsc, 'Fecha (antigua)', Icons.arrow_upward),
                    const PopupMenuDivider(),
                    _buildSortMenuItem(context, sortOption, InvoiceSortOption.clienteAsc, 'Cliente (A-Z)', Icons.sort_by_alpha),
                    _buildSortMenuItem(context, sortOption, InvoiceSortOption.clienteDesc, 'Cliente (Z-A)', Icons.sort_by_alpha),
                    const PopupMenuDivider(),
                    _buildSortMenuItem(context, sortOption, InvoiceSortOption.precioDesc, 'Precio (mayor)', Icons.arrow_downward),
                    _buildSortMenuItem(context, sortOption, InvoiceSortOption.precioAsc, 'Precio (menor)', Icons.arrow_upward),
                  ],
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'renumber') {
                      _showRenumberDialog(context, ref);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'renumber',
                      child: Row(
                        children: [
                          Icon(Icons.format_list_numbered, size: 20),
                          SizedBox(width: 12),
                          Text('Reenumerar facturas'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          // Filtros
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: AppStrings.todas,
                    selected: filter == null,
                    onTap: () =>
                        ref.read(_filterProvider.notifier).state = null,
                  ),
                  _FilterChip(
                    label: AppStrings.borrador,
                    selected: filter == InvoiceStatus.borrador,
                    onTap: () => ref.read(_filterProvider.notifier).state =
                        InvoiceStatus.borrador,
                  ),
                  _FilterChip(
                    label: AppStrings.enviada,
                    selected: filter == InvoiceStatus.enviada,
                    onTap: () => ref.read(_filterProvider.notifier).state =
                        InvoiceStatus.enviada,
                  ),
                  _FilterChip(
                    label: AppStrings.pagada,
                    selected: filter == InvoiceStatus.pagada,
                    onTap: () => ref.read(_filterProvider.notifier).state =
                        InvoiceStatus.pagada,
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: clientsCacheAsync.when(
              data: (clientsMap) => invoicesAsync.when(
                data: (invoices) {
                  var filtered = filter == null
                      ? invoices.toList()
                      : invoices.where((i) => i.status == filter).toList();

                  // Aplicar ordenación
                  filtered.sort((a, b) {
                    switch (sortOption) {
                      case InvoiceSortOption.fechaDesc:
                        return b.fecha.compareTo(a.fecha);
                      case InvoiceSortOption.fechaAsc:
                        return a.fecha.compareTo(b.fecha);
                      case InvoiceSortOption.clienteAsc:
                        final clientA = clientsMap[a.clientId]?.alias ?? '';
                        final clientB = clientsMap[b.clientId]?.alias ?? '';
                        return clientA.toLowerCase().compareTo(clientB.toLowerCase());
                      case InvoiceSortOption.clienteDesc:
                        final clientA = clientsMap[a.clientId]?.alias ?? '';
                        final clientB = clientsMap[b.clientId]?.alias ?? '';
                        return clientB.toLowerCase().compareTo(clientA.toLowerCase());
                      case InvoiceSortOption.precioDesc:
                        return b.total.compareTo(a.total);
                      case InvoiceSortOption.precioAsc:
                        return a.total.compareTo(b.total);
                    }
                  });

                  if (filtered.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: AppStrings.sinFacturas,
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final inv = filtered[index];
                      return _InvoiceTile(
                        invoice: inv,
                        selectionMode: selectionMode,
                        isSelected: selectedInvoices.contains(inv.id),
                        onSelect: (selected) {
                          final current = ref.read(_selectedInvoicesProvider);
                          if (selected) {
                            ref.read(_selectedInvoicesProvider.notifier).state = {...current, inv.id};
                          } else {
                            ref.read(_selectedInvoicesProvider.notifier).state = current.where((id) => id != inv.id).toSet();
                          }
                        },
                        onLongPress: () {
                          if (!selectionMode) {
                            ref.read(_selectionModeProvider.notifier).state = true;
                            ref.read(_selectedInvoicesProvider.notifier).state = {inv.id};
                          }
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildSelectionAppBar(BuildContext context, WidgetRef ref, Set<String> selectedInvoices) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          ref.read(_selectionModeProvider.notifier).state = false;
          ref.read(_selectedInvoicesProvider.notifier).state = {};
        },
      ),
      title: Text('${selectedInvoices.length} seleccionadas'),
      actions: [
        // Marcar como enviada
        IconButton(
          icon: const Icon(Icons.send),
          tooltip: 'Marcar como enviada',
          onPressed: selectedInvoices.isEmpty
              ? null
              : () => _bulkMarkAs(context, ref, selectedInvoices, InvoiceStatus.enviada),
        ),
        // Marcar como pagada
        IconButton(
          icon: const Icon(Icons.check_circle),
          tooltip: 'Marcar como pagada',
          onPressed: selectedInvoices.isEmpty
              ? null
              : () => _bulkMarkAs(context, ref, selectedInvoices, InvoiceStatus.pagada),
        ),
        // Revertir estado
        IconButton(
          icon: const Icon(Icons.undo),
          tooltip: 'Revertir estado',
          onPressed: selectedInvoices.isEmpty
              ? null
              : () => _bulkRevert(context, ref, selectedInvoices),
        ),
        // Seleccionar todas
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value == 'selectAll') {
              final invoices = ref.read(invoicesProvider).valueOrNull ?? [];
              ref.read(_selectedInvoicesProvider.notifier).state = 
                  invoices.map((i) => i.id).toSet();
            } else if (value == 'deselectAll') {
              ref.read(_selectedInvoicesProvider.notifier).state = {};
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'selectAll',
              child: Row(
                children: [
                  Icon(Icons.select_all, size: 20),
                  SizedBox(width: 12),
                  Text('Seleccionar todas'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'deselectAll',
              child: Row(
                children: [
                  Icon(Icons.deselect, size: 20),
                  SizedBox(width: 12),
                  Text('Deseleccionar todas'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _bulkMarkAs(BuildContext context, WidgetRef ref, Set<String> ids, InvoiceStatus status) async {
    final statusLabel = status == InvoiceStatus.enviada ? 'enviadas' : 'pagadas';
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Marcar ${ids.length} facturas como $statusLabel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final invoices = ref.read(invoicesProvider).valueOrNull ?? [];
      
      for (final id in ids) {
        final invoice = invoices.firstWhere((i) => i.id == id, orElse: () => throw Exception());
        
        // Actualizar factura
        await ref.read(invoicesProvider.notifier).updateStatus(id, status);
        
        // Actualizar gig asociado
        final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
        if (gig != null) {
          GigStatus newGigStatus;
          if (status == InvoiceStatus.enviada) {
            newGigStatus = GigStatus.facturaEnviada;
            // Programar recordatorio
            final settings = await ref.read(settingsProvider.future);
            if (settings.notificacionesActivas) {
              final client = await ref.read(clientByIdProvider(invoice.clientId).future);
              if (client != null) {
                await NotificationService.instance.schedulePaymentReminder(
                  id: invoice.numero,
                  clientName: client.nombre,
                  total: invoice.total,
                  invoiceNumber: invoice.numero,
                  scheduledDate: DateTime.now().add(Duration(days: settings.diasRecordatorio)),
                );
              }
            }
          } else {
            newGigStatus = GigStatus.pagado;
            await NotificationService.instance.cancelNotification(invoice.numero);
          }
          
          await ref.read(gigsProvider.notifier).updateStatus(gig.id, newGigStatus);
          await _syncGigToCalendar(ref, gig.copyWith(status: newGigStatus));
        }
      }
      
      ref.read(_selectionModeProvider.notifier).state = false;
      ref.read(_selectedInvoicesProvider.notifier).state = {};
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ids.length} facturas marcadas como $statusLabel')),
        );
      }
    }
  }

  Future<void> _bulkRevert(BuildContext context, WidgetRef ref, Set<String> ids) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Revertir estado de ${ids.length} facturas?'),
        content: const Text('Pagada → Enviada\nEnviada → Borrador'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final invoices = ref.read(invoicesProvider).valueOrNull ?? [];
      int count = 0;
      
      for (final id in ids) {
        final invoice = invoices.firstWhere((i) => i.id == id, orElse: () => throw Exception());
        InvoiceStatus? newStatus;
        GigStatus? newGigStatus;
        
        if (invoice.status == InvoiceStatus.pagada) {
          newStatus = InvoiceStatus.enviada;
          newGigStatus = GigStatus.facturaEnviada;
        } else if (invoice.status == InvoiceStatus.enviada) {
          newStatus = InvoiceStatus.borrador;
          newGigStatus = GigStatus.facturaGenerada;
        }
        
        if (newStatus != null) {
          await ref.read(invoicesProvider.notifier).updateStatus(id, newStatus);
          
          // Actualizar gig asociado
          final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
          if (gig != null && newGigStatus != null) {
            await ref.read(gigsProvider.notifier).updateStatus(gig.id, newGigStatus);
            await _syncGigToCalendar(ref, gig.copyWith(status: newGigStatus));
          }
          
          count++;
        }
      }
      
      ref.read(_selectionModeProvider.notifier).state = false;
      ref.read(_selectedInvoicesProvider.notifier).state = {};
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count facturas revertidas')),
        );
      }
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

  PopupMenuItem<InvoiceSortOption> _buildSortMenuItem(
    BuildContext context,
    InvoiceSortOption current,
    InvoiceSortOption option,
    String label,
    IconData icon,
  ) {
    final isSelected = current == option;
    return PopupMenuItem(
      value: option,
      child: Row(
        children: [
          Icon(icon, size: 20, color: isSelected ? AppColors.primary : null),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.primary : null,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check, size: 18, color: AppColors.primary),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  final Invoice invoice;
  final bool selectionMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelect;
  final VoidCallback? onLongPress;
  
  const _InvoiceTile({
    required this.invoice,
    this.selectionMode = false,
    this.isSelected = false,
    this.onSelect,
    this.onLongPress,
  });

  Color get _statusBgColor {
    switch (invoice.status) {
      case InvoiceStatus.borrador:
        return AppColors.draftBg;
      case InvoiceStatus.enviada:
        return AppColors.warningBg;
      case InvoiceStatus.pagada:
        return AppColors.successBg;
    }
  }

  Color get _statusTextColor {
    switch (invoice.status) {
      case InvoiceStatus.borrador:
        return AppColors.draft;
      case InvoiceStatus.enviada:
        return AppColors.warning;
      case InvoiceStatus.pagada:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(invoice.clientId));

    return Card(
      color: isSelected ? AppColors.primaryLight : null,
      child: ListTile(
        onTap: selectionMode
            ? () => onSelect?.call(!isSelected)
            : () => context.push('/invoice/${invoice.id}'),
        onLongPress: onLongPress,
        leading: selectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (v) => onSelect?.call(v ?? false),
                activeColor: AppColors.primary,
              )
            : Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _statusBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '#${invoice.numero}',
                    style: TextStyle(
                      color: _statusTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
        title: clientAsync.when(
          data: (c) => Text(c?.alias.isNotEmpty == true ? c!.alias : c?.nombre ?? ''),
          loading: () => const Text('...'),
          error: (_, __) => const Text('Error'),
        ),
        subtitle: Text(DateFormatter.dayOfWeekFull(invoice.fecha)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              CurrencyFormatter.format(invoice.total),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _statusBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                invoice.status.label,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _statusTextColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showRenumberDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController(text: '1');
  
  final startNumber = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reenumerar facturas'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Esto reenumerará todas las facturas en orden cronológico (por fecha de factura).',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Empezar desde',
              hintText: 'Ej: 1',
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Esta acción modificará todos los números de factura.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
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
          child: const Text('Reenumerar'),
        ),
      ],
    ),
  );

  if (startNumber != null && context.mounted) {
    // Confirmación adicional
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Confirmar reenumeración?'),
        content: Text(
          'Las facturas se reenumerarán empezando desde el número $startNumber, ordenadas por fecha.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await ref.read(invoicesProvider.notifier).renumberAll(startNumber);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Facturas reenumeradas correctamente')),
        );
      }
    }
  }
}
