import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/invoice.dart';
import '../../models/gig.dart';
import '../../providers/invoice_email_log_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/notification_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import '../../services/import_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/skeleton_loading.dart';
import '../../core/utils/app_haptics.dart';
import '../../models/client.dart';
import 'package:share_plus/share_plus.dart';

final _filterProvider = StateProvider<InvoiceStatus?>((ref) => null);
final _invoiceYearFilterProvider = StateProvider<int?>((ref) => null);
final _invoiceMonthFilterProvider = StateProvider<int?>((ref) => null);
final _invoiceClientFilterProvider = StateProvider<String?>((ref) => null);

void _clearAllInvoiceFilters(WidgetRef ref) {
  ref.read(_filterProvider.notifier).state = null;
  ref.read(_invoiceYearFilterProvider.notifier).state = null;
  ref.read(_invoiceMonthFilterProvider.notifier).state = null;
  ref.read(_invoiceClientFilterProvider.notifier).state = null;
}

enum InvoiceSortOption {
  fechaDesc,
  fechaAsc,
  clienteAsc,
  clienteDesc,
  precioDesc,
  precioAsc,
}

final _sortProvider = StateProvider<InvoiceSortOption>(
  (ref) => InvoiceSortOption.fechaDesc,
);

// Modo selección masiva
final _selectionModeProvider = StateProvider<bool>((ref) => false);
final _selectedInvoicesProvider = StateProvider<Set<String>>((ref) => {});

// Cache para nombres de clientes en ordenación
final _clientsCacheProvider = FutureProvider<Map<String, Client>>((ref) async {
  final clients = await ref.watch(clientsProvider.future);
  return {for (var c in clients) c.id: c};
});

class InvoicesListScreen extends ConsumerStatefulWidget {
  const InvoicesListScreen({super.key});

  @override
  ConsumerState<InvoicesListScreen> createState() => _InvoicesListScreenState();
}

class _InvoicesListScreenState extends ConsumerState<InvoicesListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        ref
            .read(invoicesProvider.notifier)
            .refreshFromCloud(reason: 'invoices_screen_open'),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider);
    final filter = ref.watch(_filterProvider);
    final sortOption = ref.watch(_sortProvider);
    final clientsCacheAsync = ref.watch(_clientsCacheProvider);
    final selectionMode = ref.watch(_selectionModeProvider);
    final selectedInvoices = ref.watch(_selectedInvoicesProvider);
    final selectedYear = ref.watch(_invoiceYearFilterProvider);
    final selectedMonth = ref.watch(_invoiceMonthFilterProvider);
    final clientFilter = ref.watch(_invoiceClientFilterProvider);
    final clientsAsync = ref.watch(clientsProvider);

    final hasActiveFilters =
        filter != null ||
        selectedYear != null ||
        selectedMonth != null ||
        clientFilter != null;

    return Scaffold(
      body: Column(
        children: [
          selectionMode
              ? _buildSelectionHeader(context, ref, selectedInvoices)
              : _buildHeader(),
          Expanded(
            child: invoicesAsync.when(
              data: (allInvoices) {
                final clients = clientsAsync.valueOrNull ?? [];
                final clientMap = {for (final c in clients) c.id: c};
                final clientsMap = clientsCacheAsync.valueOrNull ?? {};

                // Totales sin filtrar
                final totalCount = allInvoices.length;

                // Aplicar todos los filtros
                var filtered = allInvoices.where((inv) {
                  if (filter != null && inv.status != filter) return false;
                  if (selectedYear != null && inv.fecha.year != selectedYear) {
                    return false;
                  }
                  if (selectedMonth != null &&
                      inv.fecha.month != selectedMonth) {
                    return false;
                  }
                  if (clientFilter != null && inv.clientId != clientFilter) {
                    return false;
                  }
                  return true;
                }).toList();

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
                      return clientA.toLowerCase().compareTo(
                        clientB.toLowerCase(),
                      );
                    case InvoiceSortOption.clienteDesc:
                      final clientA = clientsMap[a.clientId]?.alias ?? '';
                      final clientB = clientsMap[b.clientId]?.alias ?? '';
                      return clientB.toLowerCase().compareTo(
                        clientA.toLowerCase(),
                      );
                    case InvoiceSortOption.precioDesc:
                      return b.total.compareTo(a.total);
                    case InvoiceSortOption.precioAsc:
                      return a.total.compareTo(b.total);
                  }
                });

                final filteredCount = filtered.length;
                final filteredTotal = filtered.fold<double>(
                  0,
                  (sum, inv) => sum + inv.total,
                );

                // Conteos por año
                final yearCounts = <int, int>{};
                for (final inv in allInvoices) {
                  yearCounts[inv.fecha.year] =
                      (yearCounts[inv.fecha.year] ?? 0) + 1;
                }

                // Meses con datos
                final monthsWithData = <int, int>{};
                for (final inv in allInvoices) {
                  if (selectedYear == null || inv.fecha.year == selectedYear) {
                    monthsWithData[inv.fecha.month] =
                        (monthsWithData[inv.fecha.month] ?? 0) + 1;
                  }
                }

                // Conteo por cliente
                final clientInvoiceCounts = <String, int>{};
                for (final inv in allInvoices) {
                  clientInvoiceCounts[inv.clientId] =
                      (clientInvoiceCounts[inv.clientId] ?? 0) + 1;
                }

                // Nombre del cliente filtrado
                String? clientFilterName;
                if (clientFilter != null &&
                    clientMap.containsKey(clientFilter)) {
                  clientFilterName = clientMap[clientFilter]!.alias.isNotEmpty
                      ? clientMap[clientFilter]!.alias
                      : clientMap[clientFilter]!.nombre;
                }

                // Label de mes filtrado
                String? monthLabel;
                if (selectedMonth != null) {
                  final m = DateFormat.MMM(
                    'es',
                  ).format(DateTime(2024, selectedMonth));
                  monthLabel = m[0].toUpperCase() + m.substring(1);
                }

                return Column(
                  children: [
                    // ── Resumen dinámico ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      color: AppColors.primaryLight,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.receipt_long,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$filteredCount facturas',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '·',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            CurrencyFormatter.format(filteredTotal),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          if (hasActiveFilters) ...[
                            const SizedBox(width: 8),
                            Text(
                              '[de $totalCount]',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (!selectionMode)
                      _buildInvoiceActions(context, ref, sortOption),

                    // ── Fila 1: Chips de estado ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _FilterChip(
                              label: AppStrings.todas,
                              selected: filter == null,
                              onTap: () =>
                                  ref.read(_filterProvider.notifier).state =
                                      null,
                            ),
                            _FilterChip(
                              label: AppStrings.borrador,
                              selected: filter == InvoiceStatus.borrador,
                              onTap: () =>
                                  ref.read(_filterProvider.notifier).state =
                                      InvoiceStatus.borrador,
                            ),
                            _FilterChip(
                              label: AppStrings.enviada,
                              selected: filter == InvoiceStatus.enviada,
                              onTap: () =>
                                  ref.read(_filterProvider.notifier).state =
                                      InvoiceStatus.enviada,
                            ),
                            _FilterChip(
                              label: AppStrings.pagada,
                              selected: filter == InvoiceStatus.pagada,
                              onTap: () =>
                                  ref.read(_filterProvider.notifier).state =
                                      InvoiceStatus.pagada,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Fila 2: Botones de filtro secundarios ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _SecondaryFilterButton(
                              icon: Icons.calendar_today,
                              label: selectedYear?.toString() ?? 'Año',
                              active: selectedYear != null,
                              onTap: () => _showInvoiceYearSheet(
                                context,
                                ref,
                                yearCounts,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SecondaryFilterButton(
                              icon: Icons.date_range,
                              label: monthLabel ?? 'Mes',
                              active: selectedMonth != null,
                              onTap: () => _showInvoiceMonthSheet(
                                context,
                                ref,
                                monthsWithData,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SecondaryFilterButton(
                              icon: Icons.person,
                              label: clientFilterName ?? 'Cliente',
                              active: clientFilter != null,
                              onTap: () => _showInvoiceClientSheet(
                                context,
                                ref,
                                clients,
                                clientInvoiceCounts,
                              ),
                            ),
                            if (hasActiveFilters) ...[
                              const SizedBox(width: 8),
                              _InvClearFiltersButton(
                                onTap: () => _clearAllInvoiceFilters(ref),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    if (selectionMode)
                      _buildSelectionBottomBar(context, ref, selectedInvoices),

                    // ── Lista o empty state ──
                    if (filtered.isEmpty)
                      const Expanded(
                        child: EmptyState(
                          icon: Icons.receipt_long_outlined,
                          message: AppStrings.sinFacturas,
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ).copyWith(bottom: selectionMode ? 16 : 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final inv = filtered[index];
                            return _InvoiceTile(
                              invoice: inv,
                              selectionMode: selectionMode,
                              isSelected: selectedInvoices.contains(inv.id),
                              onSelect: (selected) {
                                final current = ref.read(
                                  _selectedInvoicesProvider,
                                );
                                if (selected) {
                                  ref
                                      .read(_selectedInvoicesProvider.notifier)
                                      .state = {
                                    ...current,
                                    inv.id,
                                  };
                                } else {
                                  ref
                                      .read(_selectedInvoicesProvider.notifier)
                                      .state = current
                                      .where((id) => id != inv.id)
                                      .toSet();
                                }
                              },
                              onLongPress: () {
                                if (!selectionMode) {
                                  ref
                                          .read(_selectionModeProvider.notifier)
                                          .state =
                                      true;
                                  ref
                                      .read(_selectedInvoicesProvider.notifier)
                                      .state = {
                                    inv.id,
                                  };
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
              loading: () => Column(
                children: List.generate(5, (_) => const InvoiceCardSkeleton()),
              ),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              AppStrings.facturas,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceActions(
    BuildContext context,
    WidgetRef ref,
    InvoiceSortOption sortOption,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _InlineActionButton(
            icon: Icons.checklist,
            label: 'Seleccionar',
            onTap: () {
              ref.read(_selectionModeProvider.notifier).state = true;
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<InvoiceSortOption>(
              onSelected: (value) {
                ref.read(_sortProvider.notifier).state = value;
              },
              itemBuilder: (context) => [
                _buildSortMenuItem(
                  context,
                  sortOption,
                  InvoiceSortOption.fechaDesc,
                  'Fecha (reciente)',
                  Icons.arrow_downward,
                ),
                _buildSortMenuItem(
                  context,
                  sortOption,
                  InvoiceSortOption.fechaAsc,
                  'Fecha (antigua)',
                  Icons.arrow_upward,
                ),
                const PopupMenuDivider(),
                _buildSortMenuItem(
                  context,
                  sortOption,
                  InvoiceSortOption.clienteAsc,
                  'Cliente (A-Z)',
                  Icons.sort_by_alpha,
                ),
                _buildSortMenuItem(
                  context,
                  sortOption,
                  InvoiceSortOption.clienteDesc,
                  'Cliente (Z-A)',
                  Icons.sort_by_alpha,
                ),
                const PopupMenuDivider(),
                _buildSortMenuItem(
                  context,
                  sortOption,
                  InvoiceSortOption.precioDesc,
                  'Precio (mayor)',
                  Icons.arrow_downward,
                ),
                _buildSortMenuItem(
                  context,
                  sortOption,
                  InvoiceSortOption.precioAsc,
                  'Precio (menor)',
                  Icons.arrow_upward,
                ),
              ],
              child: const _InlineActionButtonContent(
                icon: Icons.sort,
                label: 'Ordenar',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'renumber') {
                  _showRenumberDialog(context, ref);
                } else if (value == 'apply_excel_numbering') {
                  _showApplyExcelNumberingDialog(context, ref);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'apply_excel_numbering',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file, size: 20),
                      SizedBox(width: 12),
                      Text('Aplicar numeración desde Excel'),
                    ],
                  ),
                ),
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
              child: const _InlineActionButtonContent(
                icon: Icons.more_horiz,
                label: 'Más',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionHeader(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedInvoices,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Text(
          '${selectedInvoices.length} seleccionadas',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedInvoices,
  ) {
    final hasSelection = selectedInvoices.isNotEmpty;

    return Builder(
      builder: (actionContext) => Material(
        color: AppColors.surface,
        child: Container(
          height: 70,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              _SelectionBottomAction(
                icon: Icons.close,
                label: 'Cancelar',
                onTap: () {
                  ref.read(_selectionModeProvider.notifier).state = false;
                  ref.read(_selectedInvoicesProvider.notifier).state = {};
                },
              ),
              _SelectionBottomAction(
                icon: Icons.ios_share,
                label: 'Enviar',
                enabled: hasSelection,
                onTap: () {
                  _showSelectionActionFeedback(
                    actionContext,
                    'Preparando envío',
                  );
                  _bulkShareInvoices(actionContext, ref, selectedInvoices);
                },
              ),
              _SelectionBottomAction(
                icon: Icons.check_circle,
                label: 'Cobrar',
                enabled: hasSelection,
                onTap: () {
                  _showSelectionActionFeedback(actionContext, 'Cambiar estado');
                  _bulkMarkAs(
                    actionContext,
                    ref,
                    selectedInvoices,
                    InvoiceStatus.pagada,
                  );
                },
              ),
              _SelectionBottomAction(
                icon: Icons.undo,
                label: 'Revertir',
                enabled: hasSelection,
                onTap: () {
                  _showSelectionActionFeedback(
                    actionContext,
                    'Revertir estado',
                  );
                  _bulkRevert(actionContext, ref, selectedInvoices);
                },
              ),
              Expanded(
                child: PopupMenuButton<String>(
                  enabled: hasSelection,
                  onSelected: (value) async {
                    if (value == 'selectAll') {
                      final invoices =
                          ref.read(invoicesProvider).valueOrNull ?? [];
                      ref.read(_selectedInvoicesProvider.notifier).state =
                          invoices.map((i) => i.id).toSet();
                    } else if (value == 'deselectAll') {
                      ref.read(_selectedInvoicesProvider.notifier).state = {};
                    } else if (value == 'markPending') {
                      await _bulkMarkAs(
                        actionContext,
                        ref,
                        selectedInvoices,
                        InvoiceStatus.enviada,
                      );
                    } else if (value == 'sendEmail') {
                      await _bulkEmailInvoices(
                        actionContext,
                        ref,
                        selectedInvoices,
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'sendEmail',
                      child: Row(
                        children: [
                          Icon(Icons.mark_email_read_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('Enviar por email'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'markPending',
                      child: Row(
                        children: [
                          Icon(Icons.send, size: 20),
                          SizedBox(width: 12),
                          Text('Marcar como pendiente'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
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
                  child: _SelectionBottomActionContent(
                    icon: Icons.more_horiz,
                    label: 'Más',
                    enabled: hasSelection,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSelectionActionFeedback(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 700),
        ),
      );
  }

  Future<void> _bulkShareInvoices(
    BuildContext context,
    WidgetRef ref,
    Set<String> ids,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);

    try {
      final invoices = ref.read(invoicesProvider).valueOrNull ?? [];
      final selected =
          invoices.where((invoice) => ids.contains(invoice.id)).toList()
            ..sort((a, b) => a.numero.compareTo(b.numero));
      final settings = await ref.read(settingsProvider.future);
      final files = <XFile>[];

      for (final invoice in selected) {
        final client = await ref.read(
          clientByIdProvider(invoice.clientId).future,
        );
        if (client == null) continue;
        final file = await PdfService().generateInvoicePdf(
          invoice: invoice,
          client: client,
          settings: settings,
        );
        files.add(XFile(file.path));
      }

      if (files.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudieron generar PDFs')),
          );
        }
        return;
      }

      await Share.shareXFiles(files, sharePositionOrigin: shareOrigin);

      ref.read(_selectionModeProvider.notifier).state = false;
      ref.read(_selectedInvoicesProvider.notifier).state = {};
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error enviando facturas: $e')));
      }
    }
  }

  Future<void> _bulkEmailInvoices(
    BuildContext context,
    WidgetRef ref,
    Set<String> ids,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Enviar ${ids.length} facturas por email?'),
        content: const Text(
          'Se enviará cada factura al email configurado en su cliente.',
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

    final invoices = ref.read(invoicesProvider).valueOrNull ?? [];
    final selected =
        invoices.where((invoice) => ids.contains(invoice.id)).toList()
          ..sort((a, b) => a.numero.compareTo(b.numero));
    var sent = 0;
    var failed = 0;

    for (final invoice in selected) {
      try {
        await ref.read(invoiceEmailSendProvider.notifier).send(invoice);
        sent++;

        final client = await ref.read(
          clientByIdProvider(invoice.clientId).future,
        );
        final settings = await ref.read(settingsProvider.future);
        if (client != null && settings.notificacionesActivas) {
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

        final gig = await ref.read(gigByIdProvider(invoice.gigId).future);
        if (gig != null) {
          await _syncGigToCalendar(
            ref,
            gig.copyWith(status: GigStatus.facturaEnviada),
          );
        }
      } catch (_) {
        failed++;
      }
    }

    ref.read(_selectionModeProvider.notifier).state = false;
    ref.read(_selectedInvoicesProvider.notifier).state = {};

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Emails enviados: $sent · fallidos: $failed')),
      );
    }
  }

  Future<void> _bulkMarkAs(
    BuildContext context,
    WidgetRef ref,
    Set<String> ids,
    InvoiceStatus status,
  ) async {
    final statusLabel = status == InvoiceStatus.enviada
        ? 'pendientes'
        : 'cobradas';

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
        final invoice = invoices.firstWhere(
          (i) => i.id == id,
          orElse: () => throw Exception(),
        );

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
            await NotificationService.instance.cancelNotification(
              invoice.numero,
            );
          }

          await ref
              .read(gigsProvider.notifier)
              .updateStatus(gig.id, newGigStatus);
          await _syncGigToCalendar(ref, gig.copyWith(status: newGigStatus));
        }
      }

      ref.read(_selectionModeProvider.notifier).state = false;
      ref.read(_selectedInvoicesProvider.notifier).state = {};

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} facturas marcadas como $statusLabel'),
          ),
        );
      }
    }
  }

  Future<void> _bulkRevert(
    BuildContext context,
    WidgetRef ref,
    Set<String> ids,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Revertir estado de ${ids.length} facturas?'),
        content: const Text('Cobrada → Pendiente\nPendiente → Borrador'),
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
        final invoice = invoices.firstWhere(
          (i) => i.id == id,
          orElse: () => throw Exception(),
        );
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
            await ref
                .read(gigsProvider.notifier)
                .updateStatus(gig.id, newGigStatus);
            await _syncGigToCalendar(ref, gig.copyWith(status: newGigStatus));
          }

          count++;
        }
      }

      ref.read(_selectionModeProvider.notifier).state = false;
      ref.read(_selectedInvoicesProvider.notifier).state = {};

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$count facturas revertidas')));
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

  // ─── Bottom sheets para filtros ───

  void _showInvoiceYearSheet(
    BuildContext context,
    WidgetRef ref,
    Map<int, int> yearCounts,
  ) {
    final sortedYears = yearCounts.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final selectedYear = ref.read(_invoiceYearFilterProvider);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Filtrar por año',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<int?>(
              groupValue: selectedYear,
              onChanged: (value) {
                ref.read(_invoiceYearFilterProvider.notifier).state = value;
                ref.read(_invoiceMonthFilterProvider.notifier).state = null;
                Navigator.pop(ctx);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile<int?>(
                    title: Text('Todos los años'),
                    value: null,
                  ),
                  ...sortedYears.map(
                    (year) => RadioListTile<int?>(
                      title: Text(year.toString()),
                      subtitle: Text('${yearCounts[year]} facturas'),
                      value: year,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInvoiceMonthSheet(
    BuildContext context,
    WidgetRef ref,
    Map<int, int> monthsWithData,
  ) {
    final selectedMonth = ref.read(_invoiceMonthFilterProvider);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filtrar por mes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(
                selectedMonth == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selectedMonth == null
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              title: const Text('Todos los meses'),
              contentPadding: EdgeInsets.zero,
              onTap: () {
                ref.read(_invoiceMonthFilterProvider.notifier).state = null;
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                childAspectRatio: 1.6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final hasData = monthsWithData.containsKey(month);
                final isSelected = selectedMonth == month;
                final raw = DateFormat.MMM('es').format(DateTime(2024, month));
                final name = raw[0].toUpperCase() + raw.substring(1);

                return GestureDetector(
                  onTap: hasData
                      ? () {
                          ref.read(_invoiceMonthFilterProvider.notifier).state =
                              month;
                          Navigator.pop(ctx);
                        }
                      : null,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : hasData
                          ? AppColors.primaryLight
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : hasData
                            ? AppColors.cardBorder
                            : AppColors.divider,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : hasData
                                ? AppColors.textPrimary
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.4,
                                  ),
                          ),
                        ),
                        if (hasData)
                          Text(
                            '${monthsWithData[month]}',
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.white70
                                  : AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showInvoiceClientSheet(
    BuildContext context,
    WidgetRef ref,
    List<Client> clients,
    Map<String, int> invoiceCounts,
  ) {
    final clientsWithInvoices =
        clients.where((c) => (invoiceCounts[c.id] ?? 0) > 0).toList()..sort(
          (a, b) =>
              (invoiceCounts[b.id] ?? 0).compareTo(invoiceCounts[a.id] ?? 0),
        );

    final selectedClientId = ref.read(_invoiceClientFilterProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => _InvClientSheetContent(
          clients: clientsWithInvoices,
          invoiceCounts: invoiceCounts,
          selectedClientId: selectedClientId,
          scrollController: scrollController,
          onSelect: (clientId) {
            ref.read(_invoiceClientFilterProvider.notifier).state = clientId;
            Navigator.pop(ctx);
          },
        ),
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

class _InlineActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _InlineActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: _InlineActionButtonContent(icon: icon, label: label),
        ),
      ),
    );
  }
}

class _InlineActionButtonContent extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InlineActionButtonContent({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.noScaling),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _SelectionBottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: _SelectionBottomActionContent(
            icon: icon,
            label: label,
            enabled: enabled,
          ),
        ),
      ),
    );
  }
}

class _SelectionBottomActionContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _SelectionBottomActionContent({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.primary
        : AppColors.textSecondary.withValues(alpha: 0.4);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(
        height: 74,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
            : () {
                AppHaptics.light();
                context.push('/invoice/${invoice.id}');
              },
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
          data: (c) =>
              Text(c?.alias.isNotEmpty == true ? c!.alias : c?.nombre ?? ''),
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
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _statusTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showRenumberDialog(BuildContext context, WidgetRef ref) async {
  final selectedYear = ref.read(_invoiceYearFilterProvider);
  final year = selectedYear ?? DateTime.now().year;

  final shouldRenumber = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reenumerar facturas'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Esto reenumerará las facturas del año seleccionado en orden cronológico.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'Año: $year',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Esta acción modificará solo los números de factura de ese año y empezará en 1.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (selectedYear == null) ...[
            const SizedBox(height: 8),
            Text(
              'No hay filtro de año activo, se usará $year.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Reenumerar'),
        ),
      ],
    ),
  );

  if (shouldRenumber == true && context.mounted) {
    // Confirmación adicional
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Confirmar reenumeración?'),
        content: Text(
          'Las facturas de $year se reenumerarán del 1 en adelante, ordenadas por fecha.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await ref.read(invoicesProvider.notifier).renumberYear(year);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Facturas de $year reenumeradas correctamente'),
          ),
        );
      }
    }
  }
}

Future<void> _showApplyExcelNumberingDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final selectedYear = ref.read(_invoiceYearFilterProvider);
  final year = selectedYear ?? DateTime.now().year;

  final pick = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls'],
  );
  if (pick == null || pick.files.isEmpty) return;
  final path = pick.files.first.path;
  if (path == null) return;
  final bytes = await File(path).readAsBytes();

  final preview = await ImportService.previewApplyNumberingFromExcel(
    bytes: bytes,
    year: year,
  );

  if (!context.mounted) return;
  if (preview.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sin cambios de numeración desde Excel en $year')),
    );
    return;
  }

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Aplicar numeración Excel ($year)'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Preview:'),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: preview
                      .take(30)
                      .map(
                        (p) => Text('#${p.currentNumber} → #${p.excelNumber}'),
                      )
                      .toList(),
                ),
              ),
            ),
            if (preview.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('+ ${preview.length - 30} cambios más'),
              ),
            const SizedBox(height: 8),
            const Text(
              'Se respeta número exacto del Excel. Se permiten huecos.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
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

  if (confirm != true || !context.mounted) return;

  final updated = await ref
      .read(invoicesProvider.notifier)
      .applyExcelNumberingPreview(year, preview);

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Numeración Excel aplicada: $updated facturas')),
  );
}

// ─── Widgets auxiliares para filtros secundarios ───

class _SecondaryFilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _SecondaryFilterButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final bgColor = active
        ? AppColors.warningBg
        : disabled
        ? AppColors.surface
        : AppColors.surface;
    final fgColor = active
        ? AppColors.warning
        : disabled
        ? AppColors.textSecondary.withValues(alpha: 0.5)
        : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? AppColors.warning.withValues(alpha: 0.3)
                : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fgColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: fgColor,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: fgColor),
          ],
        ),
      ),
    );
  }
}

class _InvClearFiltersButton extends StatelessWidget {
  final VoidCallback onTap;

  const _InvClearFiltersButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.errorBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close, size: 14, color: AppColors.error),
            SizedBox(width: 4),
            Text(
              'Limpiar',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvClientSheetContent extends StatefulWidget {
  final List<Client> clients;
  final Map<String, int> invoiceCounts;
  final String? selectedClientId;
  final ScrollController scrollController;
  final ValueChanged<String?> onSelect;

  const _InvClientSheetContent({
    required this.clients,
    required this.invoiceCounts,
    required this.selectedClientId,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  State<_InvClientSheetContent> createState() => _InvClientSheetContentState();
}

class _InvClientSheetContentState extends State<_InvClientSheetContent> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lower = _query.toLowerCase();
    final filtered = _query.isEmpty
        ? widget.clients
        : widget.clients.where((c) {
            if (c.nombre.toLowerCase().contains(lower)) return true;
            if (c.alias.toLowerCase().contains(lower)) return true;
            if (c.aliases.any((a) => a.toLowerCase().contains(lower))) {
              return true;
            }
            return false;
          }).toList();

    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Filtrar por cliente',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar cliente...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            children: [
              ListTile(
                leading: Icon(
                  widget.selectedClientId == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: widget.selectedClientId == null
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                title: const Text('Todos los clientes'),
                onTap: () => widget.onSelect(null),
              ),
              ...filtered.map((client) {
                final isSelected = widget.selectedClientId == client.id;
                final count = widget.invoiceCounts[client.id] ?? 0;
                final displayName = client.alias.isNotEmpty
                    ? client.alias
                    : client.nombre;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(displayName),
                  subtitle: Text('$count facturas'),
                  onTap: () => widget.onSelect(client.id),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
