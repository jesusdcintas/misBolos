import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/invoice.dart';
import '../../models/gig.dart';
import '../../providers/invoice_email_log_provider.dart';
import '../../providers/invoice_list_ui_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/pdf_service.dart';
import '../../services/notification_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/skeleton_loading.dart';
import '../../core/utils/app_haptics.dart';
import '../../models/client.dart';
import 'package:share_plus/share_plus.dart';

void _clearAllInvoiceFilters(WidgetRef ref) {
  ref.read(invoiceStatusFilterProvider.notifier).state = null;
  ref.read(invoiceYearFilterProvider.notifier).state = DateTime.now().year;
  ref.read(invoiceMonthFilterProvider.notifier).state = null;
  ref.read(invoiceClientFilterProvider.notifier).state = null;
}

enum InvoiceViewMode { list, grid }

final _viewModeProvider = StateProvider<InvoiceViewMode>(
  (ref) => InvoiceViewMode.list,
);

// Modo selección masiva
final _selectionModeProvider = StateProvider<bool>((ref) => false);
final _selectedInvoicesProvider = StateProvider<Set<String>>((ref) => {});

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

  Future<void> _refreshInvoices() async {
    await ref
        .read(invoicesProvider.notifier)
        .refreshFromCloud(reason: 'pull_to_refresh', force: true);
    ref.invalidate(invoicesProvider);
    ref.invalidate(gigsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider);
    final filter = ref.watch(invoiceStatusFilterProvider);
    final sortOption = ref.watch(invoiceSortProvider);
    final viewMode = ref.watch(_viewModeProvider);
    final selectionMode = ref.watch(_selectionModeProvider);
    final selectedInvoices = ref.watch(_selectedInvoicesProvider);
    final selectedYear = ref.watch(invoiceYearFilterProvider);
    final selectedMonth = ref.watch(invoiceMonthFilterProvider);
    final clientFilter = ref.watch(invoiceClientFilterProvider);
    final clientsAsync = ref.watch(clientsProvider);
    final pendingCount =
        ref.watch(syncQueuePendingCountProvider).valueOrNull ?? 0;

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
              : _buildHeader(pendingCount),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshInvoices,
              child: invoicesAsync.when(
                data: (allInvoices) {
                  final clients = clientsAsync.valueOrNull ?? [];
                  final clientMap = {for (final c in clients) c.id: c};

                  // Misma lista compartida para UI y detalle.
                  final filtered = ref.watch(filteredSortedInvoicesProvider);

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
                    if (selectedYear == null ||
                        inv.fecha.year == selectedYear) {
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
                            const SizedBox(width: 8),
                            const Text(
                              'IVA incluido',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (!selectionMode)
                        _buildInvoiceActions(
                          context,
                          ref,
                          sortOption,
                          viewMode,
                        ),

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
                                    ref
                                            .read(
                                              invoiceStatusFilterProvider
                                                  .notifier,
                                            )
                                            .state =
                                        null,
                              ),
                              _FilterChip(
                                label: AppStrings.borrador,
                                selected: filter == InvoiceStatus.borrador,
                                onTap: () =>
                                    ref
                                        .read(
                                          invoiceStatusFilterProvider.notifier,
                                        )
                                        .state = InvoiceStatus
                                        .borrador,
                              ),
                              _FilterChip(
                                label: AppStrings.enviada,
                                selected: filter == InvoiceStatus.enviada,
                                onTap: () =>
                                    ref
                                        .read(
                                          invoiceStatusFilterProvider.notifier,
                                        )
                                        .state = InvoiceStatus
                                        .enviada,
                              ),
                              _FilterChip(
                                label: AppStrings.pagada,
                                selected: filter == InvoiceStatus.pagada,
                                onTap: () =>
                                    ref
                                        .read(
                                          invoiceStatusFilterProvider.notifier,
                                        )
                                        .state = InvoiceStatus
                                        .pagada,
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
                        _buildSelectionBottomBar(
                          context,
                          ref,
                          selectedInvoices,
                        ),

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
                          child: _buildInvoicesContent(
                            context,
                            ref,
                            filtered,
                            selectionMode,
                            selectedInvoices,
                            viewMode,
                          ),
                        ),
                    ],
                  );
                },
                loading: () => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: List.generate(
                    5,
                    (_) => const InvoiceCardSkeleton(),
                  ),
                ),
                error: (e, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: Center(child: Text('Error: $e')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int pendingCount) {
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
          if (pendingCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.warning),
              ),
              child: Text(
                '$pendingCount',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
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
    InvoiceViewMode viewMode,
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
                ref.read(invoiceSortProvider.notifier).state = value;
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
                  InvoiceSortOption.numeroDesc,
                  'Número (mayor)',
                  Icons.pin_outlined,
                ),
                _buildSortMenuItem(
                  context,
                  sortOption,
                  InvoiceSortOption.numeroAsc,
                  'Número (menor)',
                  Icons.pin,
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
            child: PopupMenuButton<InvoiceViewMode>(
              onSelected: (value) {
                ref.read(_viewModeProvider.notifier).state = value;
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: InvoiceViewMode.list,
                  child: Row(
                    children: [
                      Icon(
                        Icons.view_agenda_outlined,
                        size: 20,
                        color: viewMode == InvoiceViewMode.list
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Lista',
                        style: TextStyle(
                          color: viewMode == InvoiceViewMode.list
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontWeight: viewMode == InvoiceViewMode.list
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: InvoiceViewMode.grid,
                  child: Row(
                    children: [
                      Icon(
                        Icons.grid_view_outlined,
                        size: 20,
                        color: viewMode == InvoiceViewMode.grid
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Cuadrícula',
                        style: TextStyle(
                          color: viewMode == InvoiceViewMode.grid
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontWeight: viewMode == InvoiceViewMode.grid
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: _InlineActionButtonContent(
                icon: viewMode == InvoiceViewMode.grid
                    ? Icons.grid_view_outlined
                    : Icons.view_agenda_outlined,
                label: viewMode == InvoiceViewMode.grid
                    ? 'Cuadrícula'
                    : 'Lista',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Builder(
              builder: (menuContext) {
                final isMobile = MediaQuery.of(menuContext).size.width < 430;
                final renumberLabel = isMobile
                    ? 'Reenumerar'
                    : 'Reenumerar facturas';
                return PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'renumber') {
                      _showRenumberDialog(context, ref);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'renumber',
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isMobile ? 190 : 280,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.format_list_numbered, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                renumberLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  child: const _InlineActionButtonContent(
                    icon: Icons.more_horiz,
                    label: 'Más',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoicesContent(
    BuildContext context,
    WidgetRef ref,
    List<Invoice> filtered,
    bool selectionMode,
    Set<String> selectedInvoices,
    InvoiceViewMode viewMode,
  ) {
    void toggleSelection(Invoice invoice, bool selected) {
      final current = ref.read(_selectedInvoicesProvider);
      if (selected) {
        ref.read(_selectedInvoicesProvider.notifier).state = {
          ...current,
          invoice.id,
        };
        return;
      }
      ref.read(_selectedInvoicesProvider.notifier).state = current
          .where((id) => id != invoice.id)
          .toSet();
    }

    void handleLongPress(Invoice invoice) {
      if (selectionMode) return;
      ref.read(_selectionModeProvider.notifier).state = true;
      ref.read(_selectedInvoicesProvider.notifier).state = {invoice.id};
    }

    if (viewMode == InvoiceViewMode.list) {
      return ListView.builder(
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
            onSelect: (selected) => toggleSelection(inv, selected),
            onLongPress: () => handleLongPress(inv),
          );
        },
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth >= 1200
        ? 4
        : screenWidth >= 900
        ? 3
        : 2;
    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
      ).copyWith(top: 4, bottom: selectionMode ? 16 : 80),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.42,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final inv = filtered[index];
        return _InvoiceGridCard(
          invoice: inv,
          selectionMode: selectionMode,
          isSelected: selectedInvoices.contains(inv.id),
          onSelect: (selected) => toggleSelection(inv, selected),
          onLongPress: () => handleLongPress(inv),
        );
      },
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
                    } else if (value == 'editConcept') {
                      await _showBulkConceptDialog(
                        actionContext,
                        ref,
                        selectedInvoices,
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'editConcept',
                      child: Row(
                        children: [
                          Icon(Icons.edit_note, size: 20),
                          SizedBox(width: 12),
                          Text('Cambiar concepto'),
                        ],
                      ),
                    ),
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
                          Text('Marcar como facturada'),
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
            gig.copyWith(status: GigStatus.facturado),
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

  Future<void> _showBulkConceptDialog(
    BuildContext context,
    WidgetRef ref,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return;
    final conceptController = TextEditingController();
    var replaceAllLines = false;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Cambiar concepto en ${ids.length} facturas'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: conceptController,
                decoration: const InputDecoration(
                  labelText: 'Nuevo concepto',
                  hintText: 'Ej: DJ SET',
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: replaceAllLines,
                contentPadding: EdgeInsets.zero,
                title: const Text('Reemplazar todas las líneas'),
                subtitle: const Text(
                  'Si está desactivado, solo cambia la primera línea.',
                ),
                onChanged: (value) {
                  setModalState(() {
                    replaceAllLines = value ?? false;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );

    final newConcept = conceptController.text.trim();
    conceptController.dispose();
    if (accepted != true || newConcept.isEmpty) return;

    final invoices = ref.read(invoicesProvider).valueOrNull ?? [];
    final selected = invoices
        .where((invoice) => ids.contains(invoice.id))
        .toList();
    if (selected.isEmpty) return;

    var updatedCount = 0;
    var skippedCount = 0;
    var failedCount = 0;

    for (final invoice in selected) {
      try {
        if (invoice.items.isEmpty) {
          skippedCount++;
          continue;
        }
        final updatedItems = <InvoiceLineItem>[];
        for (var i = 0; i < invoice.items.length; i++) {
          final line = invoice.items[i];
          final shouldReplace = replaceAllLines || i == 0;
          updatedItems.add(
            InvoiceLineItem(
              cantidad: line.cantidad,
              descripcion: shouldReplace ? newConcept : line.descripcion,
              precioUnitario: line.precioUnitario,
              totalLinea: line.totalLinea,
            ),
          );
        }

        await ref
            .read(invoicesProvider.notifier)
            .updateInvoice(invoice.copyWith(items: updatedItems));
        updatedCount++;
      } catch (_) {
        failedCount++;
      }
    }

    if (!context.mounted) return;
    final parts = <String>[
      '$updatedCount actualizadas',
      if (skippedCount > 0) '$skippedCount sin líneas',
      if (failedCount > 0) '$failedCount con error',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Concepto masivo: ${parts.join(' · ')}')),
    );
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
            newGigStatus = GigStatus.facturado;
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
            newGigStatus = GigStatus.cobrado;
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
        content: const Text(
          'Cobrada → Pendiente de cobro\nPendiente de cobro → Borrador',
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
          newGigStatus = GigStatus.facturado;
        } else if (invoice.status == InvoiceStatus.enviada) {
          newStatus = InvoiceStatus.borrador;
          newGigStatus = GigStatus.facturado;
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
    final selectedYear = ref.read(invoiceYearFilterProvider);

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
                ref.read(invoiceYearFilterProvider.notifier).state = value;
                ref.read(invoiceMonthFilterProvider.notifier).state = null;
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
    final selectedMonth = ref.read(invoiceMonthFilterProvider);

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
                ref.read(invoiceMonthFilterProvider.notifier).state = null;
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
                          ref.read(invoiceMonthFilterProvider.notifier).state =
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

    final selectedClientId = ref.read(invoiceClientFilterProvider);

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
            ref.read(invoiceClientFilterProvider.notifier).state = clientId;
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

class _InvoiceGridCard extends ConsumerWidget {
  final Invoice invoice;
  final bool selectionMode;
  final bool isSelected;
  final ValueChanged<bool>? onSelect;
  final VoidCallback? onLongPress;

  const _InvoiceGridCard({
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

  String get _conceptSummary {
    final lines = invoice.items
        .map((item) => item.descripcion.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return 'Sin concepto';
    if (lines.length == 1) return lines.first;
    return '${lines.first} +${lines.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(invoice.clientId));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: onLongPress,
        onTap: selectionMode
            ? () => onSelect?.call(!isSelected)
            : () {
                AppHaptics.light();
                context.push('/invoice/${invoice.id}');
              },
        child: Card(
          margin: EdgeInsets.zero,
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (selectionMode)
                      Checkbox(
                        value: isSelected,
                        onChanged: (v) => onSelect?.call(v ?? false),
                        activeColor: AppColors.primary,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusBgColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '#${invoice.numero}',
                          style: TextStyle(
                            color: _statusTextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _statusBgColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        invoice.status.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _statusTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                clientAsync.when(
                  data: (c) => Text(
                    c?.alias.isNotEmpty == true ? c!.alias : c?.nombre ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  loading: () => const Text('...'),
                  error: (_, __) => const Text('Error'),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormatter.dayOfWeekFull(invoice.fecha),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _conceptSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  CurrencyFormatter.format(invoice.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showRenumberDialog(BuildContext context, WidgetRef ref) async {
  final selectedYear =
      ref.read(invoiceYearFilterProvider) ?? DateTime.now().year;
  final invoices = await ref.read(invoicesProvider.future);
  final years =
      invoices
          .map((invoice) => invoice.fecha.year)
          .toSet()
          .toList(growable: false)
        ..sort((a, b) => b.compareTo(a));
  final availableYears = years.isEmpty ? <int>[selectedYear] : years;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ManualRenumberDialog(
      initialYear: selectedYear,
      availableYears: availableYears,
    ),
  );
}

class _ManualRenumberDialog extends ConsumerStatefulWidget {
  final int initialYear;
  final List<int> availableYears;

  const _ManualRenumberDialog({
    required this.initialYear,
    required this.availableYears,
  });

  @override
  ConsumerState<_ManualRenumberDialog> createState() =>
      _ManualRenumberDialogState();
}

class _ManualRenumberDialogState extends ConsumerState<_ManualRenumberDialog> {
  late int _selectedYear;
  final _reasonController = TextEditingController();
  final _tableVerticalController = ScrollController();
  final _tableHorizontalController = ScrollController();
  final _mobileListController = ScrollController();
  bool _saving = false;
  final Map<String, TextEditingController> _numberControllers = {};
  final Map<String, GlobalKey> _invoiceFieldKeys = {};

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.availableYears.contains(widget.initialYear)
        ? widget.initialYear
        : widget.availableYears.first;
  }

  @override
  void dispose() {
    for (final controller in _numberControllers.values) {
      controller.dispose();
    }
    _reasonController.dispose();
    _tableVerticalController.dispose();
    _tableHorizontalController.dispose();
    _mobileListController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(Invoice invoice) {
    return _numberControllers.putIfAbsent(
      invoice.id,
      () => TextEditingController(text: invoice.numero.toString()),
    );
  }

  GlobalKey _fieldKeyFor(String invoiceId) {
    return _invoiceFieldKeys.putIfAbsent(invoiceId, GlobalKey.new);
  }

  void _scrollFieldIntoView(String invoiceId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _fieldKeyFor(invoiceId).currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.35,
      );
    });
  }

  Future<void> _save(List<Invoice> invoices) async {
    final parsed = <String, int>{};
    final seen = <int>{};
    for (final invoice in invoices) {
      final raw = _controllerFor(invoice).text.trim();
      final number = int.tryParse(raw);
      if (number == null || number <= 0) {
        throw StateError(
          'Todos los nuevos números deben ser enteros positivos.',
        );
      }
      if (!seen.add(number)) {
        throw StateError('Hay números duplicados en la nueva numeración.');
      }
      if (invoice.fecha.year != _selectedYear) {
        throw StateError(
          'Todas las facturas deben pertenecer al mismo año fiscal.',
        );
      }
      parsed[invoice.id] = number;
    }

    final changed = invoices
        .where((invoice) => parsed[invoice.id] != invoice.numero)
        .toList(growable: false);
    if (changed.isEmpty) {
      throw StateError('No hay cambios para guardar.');
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar reenumeración fiscal'),
        content: Text(
          'Vas a modificar la numeración fiscal de ${changed.length} facturas. '
          'Esta acción debe hacerse solo para corregir errores.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(invoicesProvider.notifier)
          .renumberInvoicesManually(
            fiscalYear: _selectedYear,
            newNumbersByInvoiceId: parsed,
            reason: _reasonController.text.trim().isEmpty
                ? null
                : _reasonController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Facturas reenumeradas correctamente')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(
      invoicesByFiscalYearProvider(_selectedYear),
    );
    final clientsAsync = ref.watch(clientsProvider);
    final clients = clientsAsync.valueOrNull ?? const <Client>[];
    final clientMap = {for (final client in clients) client.id: client};
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isMobile = screenSize.width < 720;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final keyboardOpen = keyboardHeight > 0;
    final safeVertical = mediaQuery.padding.top + mediaQuery.padding.bottom;
    final verticalMargins = isMobile ? 24.0 : 48.0;
    final availableHeight =
        screenSize.height - keyboardHeight - safeVertical - verticalMargins;
    final mobileHeightLimit = screenSize.height * (keyboardOpen ? 0.68 : 0.90);
    final mobileDialogHeight = availableHeight < 280
        ? availableHeight
        : availableHeight.clamp(280.0, mobileHeightLimit);
    final maxDialogHeight = isMobile
        ? mobileDialogHeight.toDouble()
        : (screenSize.height * 0.88);
    final maxDialogWidth = isMobile ? screenSize.width * 0.95 : 1200.0;
    final compactHeader = isMobile && keyboardOpen;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 12 : 24,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: maxDialogHeight,
            ),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    compactHeader ? 10 : 16,
                    16,
                    compactHeader ? 6 : 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reenumeración manual de facturas',
                        style: TextStyle(
                          fontSize: compactHeader ? 16 : 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: compactHeader ? 6 : 12),
                      Row(
                        children: [
                          const Text('Año fiscal:'),
                          const SizedBox(width: 12),
                          DropdownButton<int>(
                            value: _selectedYear,
                            items: widget.availableYears
                                .map(
                                  (year) => DropdownMenuItem<int>(
                                    value: year,
                                    child: Text(year.toString()),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() => _selectedYear = value);
                                  },
                          ),
                        ],
                      ),
                      if (!compactHeader) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _reasonController,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Motivo (opcional)',
                            hintText:
                                'Ej: intercambio de numeración por error de emisión',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Guardando reenumeración...',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: invoicesAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (error, _) => Center(
                        child: Text('Error cargando facturas: $error'),
                      ),
                      data: (invoices) {
                        final visibleInvoices = invoices
                            .where((invoice) => invoice.numero > 0)
                            .toList(growable: false);
                        if (visibleInvoices.isEmpty) {
                          return const Center(
                            child: Text('No hay facturas en ese año fiscal.'),
                          );
                        }
                        if (isMobile) {
                          return ListView.builder(
                            controller: _mobileListController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.only(
                              bottom: keyboardOpen ? 12 : 0,
                            ),
                            itemCount: visibleInvoices.length,
                            itemBuilder: (context, index) {
                              final invoice = visibleInvoices[index];
                              final client = clientMap[invoice.clientId];
                              final clientName =
                                  client?.alias.isNotEmpty == true
                                  ? client!.alias
                                  : client?.nombre ?? invoice.clientId;
                              final controller = _controllerFor(invoice);
                              return Card(
                                key: _fieldKeyFor(invoice.id),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    compactHeader ? 10 : 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Nº actual: ${invoice.numero}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Fecha emisión: ${DateFormat('dd/MM/yyyy').format(invoice.fecha)}',
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Cliente: $clientName',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Total: ${CurrencyFormatter.format(invoice.total)}',
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Estado: ${invoice.status.label}'),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: controller,
                                        enabled: !_saving,
                                        keyboardType: TextInputType.number,
                                        scrollPadding: EdgeInsets.only(
                                          bottom: keyboardHeight + 96,
                                        ),
                                        onTap: () =>
                                            _scrollFieldIntoView(invoice.id),
                                        decoration: const InputDecoration(
                                          labelText: 'Nuevo número',
                                          isDense: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        }
                        return Scrollbar(
                          controller: _tableVerticalController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _tableVerticalController,
                            child: Scrollbar(
                              controller: _tableHorizontalController,
                              thumbVisibility: true,
                              notificationPredicate: (notification) =>
                                  notification.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: _tableHorizontalController,
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Nº actual')),
                                    DataColumn(label: Text('Fecha emisión')),
                                    DataColumn(label: Text('Cliente')),
                                    DataColumn(label: Text('Total')),
                                    DataColumn(label: Text('Estado')),
                                    DataColumn(label: Text('Nuevo nº')),
                                  ],
                                  rows: visibleInvoices
                                      .map((invoice) {
                                        final client =
                                            clientMap[invoice.clientId];
                                        final clientName =
                                            client?.alias.isNotEmpty == true
                                            ? client!.alias
                                            : client?.nombre ??
                                                  invoice.clientId;
                                        final controller = _controllerFor(
                                          invoice,
                                        );
                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Text(invoice.numero.toString()),
                                            ),
                                            DataCell(
                                              Text(
                                                DateFormat(
                                                  'dd/MM/yyyy',
                                                ).format(invoice.fecha),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 180,
                                                child: Text(
                                                  clientName,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                CurrencyFormatter.format(
                                                  invoice.total,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(invoice.status.label),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 110,
                                                child: TextField(
                                                  controller: controller,
                                                  enabled: !_saving,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      })
                                      .toList(growable: false),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final invoices = await ref.read(
                                    invoicesByFiscalYearProvider(
                                      _selectedYear,
                                    ).future,
                                  );
                                  try {
                                    await _save(invoices);
                                  } catch (error) {
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(content: Text(error.toString())),
                                    );
                                  }
                                },
                          child: _saving
                              ? const Text('Guardando...')
                              : const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
