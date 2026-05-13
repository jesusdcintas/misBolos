import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/app_haptics.dart';
import '../../models/client.dart';
import '../../models/gig.dart';
import '../../providers/gig_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/sync_provider.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/facturable_badge.dart';
import '../../widgets/common/skeleton_loading.dart';

// ─── Filter providers ───
final gigStatusFilterProvider = StateProvider<GigStatus?>((ref) => null);
final gigYearFilterProvider = StateProvider<int?>((ref) => null);
final gigMonthFilterProvider = StateProvider<int?>((ref) => null);
final gigClientFilterProvider = StateProvider<String?>((ref) => null);
final gigFacturableFilterProvider = StateProvider<bool?>((ref) => null);

enum GigSortOption { fechaAsc, fechaDesc, precioAsc, precioDesc }

final gigSortProvider = StateProvider<GigSortOption>(
  (ref) => GigSortOption.fechaAsc,
);

void _clearAllFilters(WidgetRef ref) {
  ref.read(gigStatusFilterProvider.notifier).state = null;
  ref.read(gigYearFilterProvider.notifier).state = null;
  ref.read(gigMonthFilterProvider.notifier).state = null;
  ref.read(gigClientFilterProvider.notifier).state = null;
  ref.read(gigFacturableFilterProvider.notifier).state = null;
}

class GigsListScreen extends ConsumerStatefulWidget {
  const GigsListScreen({super.key});

  @override
  ConsumerState<GigsListScreen> createState() => _GigsListScreenState();
}

class _GigsListScreenState extends ConsumerState<GigsListScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _toggleSelectAll(List<Gig> gigs) {
    setState(() {
      if (_selectedIds.length == gigs.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(gigs.map((g) => g.id));
        _selectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> _applyBulkStatus(GigStatus status) async {
    await ref
        .read(gigsProvider.notifier)
        .bulkUpdateStatus(_selectedIds, status);
    _clearSelection();
  }

  Future<void> _applyBulkFacturable(bool facturable) async {
    await ref
        .read(gigsProvider.notifier)
        .bulkSetFacturable(_selectedIds, facturable);
    _clearSelection();
  }

  Future<void> _applyBulkDelete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar bolos'),
        content: Text(
          'Se eliminarán ${_selectedIds.length} bolos. ¿Confirmas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(gigsProvider.notifier).bulkDelete(_selectedIds);
    _clearSelection();
  }

  Future<void> _refreshGigs() async {
    await ref.read(syncProvider.notifier).downloadFromCloud();
    ref.invalidate(gigsProvider);
    ref.invalidate(clientsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final gigsAsync = ref.watch(gigsProvider);
    final clientsAsync = ref.watch(clientsProvider);
    final statusFilter = ref.watch(gigStatusFilterProvider);
    final selectedYear = ref.watch(gigYearFilterProvider);
    final selectedMonth = ref.watch(gigMonthFilterProvider);
    final clientFilter = ref.watch(gigClientFilterProvider);
    final facturableFilter = ref.watch(gigFacturableFilterProvider);
    final sortOption = ref.watch(gigSortProvider);

    final hasActiveFilters =
        statusFilter != null ||
        selectedYear != null ||
        selectedMonth != null ||
        clientFilter != null ||
        facturableFilter != null;

    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _selectionMode
              ? Text(
                  '${_selectedIds.length} seleccionados',
                  key: const ValueKey('count'),
                )
              : const Text('Bolos', key: ValueKey('title')),
        ),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        actions: _selectionMode
            ? [
                TextButton(
                  onPressed: _clearSelection,
                  child: const Text('Cancelar'),
                ),
              ]
            : null,
      ),
      body: gigsAsync.when(
        data: (allGigs) {
          final clients = clientsAsync.valueOrNull ?? [];
          final clientMap = {for (final c in clients) c.id: c};

          // Totales sin filtrar
          final totalCount = allGigs.length;

          // Aplicar todos los filtros
          final filteredGigs = allGigs.where((gig) {
            if (statusFilter != null && gig.status != statusFilter) {
              return false;
            }
            if (selectedYear != null && gig.fecha.year != selectedYear) {
              return false;
            }
            if (selectedMonth != null && gig.fecha.month != selectedMonth) {
              return false;
            }
            if (clientFilter != null && gig.clientId != clientFilter) {
              return false;
            }
            if (facturableFilter != null &&
                gig.facturable != facturableFilter) {
              return false;
            }
            return true;
          }).toList();
          filteredGigs.sort((a, b) {
            switch (sortOption) {
              case GigSortOption.fechaAsc:
                return a.fecha.compareTo(b.fecha);
              case GigSortOption.fechaDesc:
                return b.fecha.compareTo(a.fecha);
              case GigSortOption.precioAsc:
                return (a.cachet ?? 0).compareTo(b.cachet ?? 0);
              case GigSortOption.precioDesc:
                return (b.cachet ?? 0).compareTo(a.cachet ?? 0);
            }
          });

          final filteredCount = filteredGigs.length;
          final filteredCachet = filteredGigs.fold<double>(
            0,
            (sum, g) => sum + (g.cachet ?? 0),
          );

          // Conteos por año (sobre todos los gigs)
          final yearCounts = <int, int>{};
          for (final gig in allGigs) {
            yearCounts[gig.fecha.year] = (yearCounts[gig.fecha.year] ?? 0) + 1;
          }

          // Meses con datos (para el año seleccionado, o todos si no hay año)
          final monthsWithData = <int, int>{};
          for (final gig in allGigs) {
            if (selectedYear == null || gig.fecha.year == selectedYear) {
              monthsWithData[gig.fecha.month] =
                  (monthsWithData[gig.fecha.month] ?? 0) + 1;
            }
          }

          // Conteo de bolos por cliente
          final clientGigCounts = <String, int>{};
          for (final gig in allGigs) {
            clientGigCounts[gig.clientId] =
                (clientGigCounts[gig.clientId] ?? 0) + 1;
          }

          // Nombre del cliente filtrado
          String? clientFilterName;
          if (clientFilter != null && clientMap.containsKey(clientFilter)) {
            clientFilterName = clientMap[clientFilter]!.nombre;
          }

          // Label de mes filtrado
          String? monthLabel;
          if (selectedMonth != null) {
            final m = DateFormat.MMM(
              'es',
            ).format(DateTime(2024, selectedMonth));
            monthLabel = m[0].toUpperCase() + m.substring(1);
          }

          return RefreshIndicator(
            onRefresh: _refreshGigs,
            child: Column(
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
                        Icons.music_note,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$filteredCount bolos',
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
                        CurrencyFormatter.format(filteredCachet),
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

                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _InlineActionButton(
                        icon: Icons.checklist,
                        label: _selectionMode ? 'Cancelar' : 'Seleccionar',
                        onTap: _selectionMode
                            ? _clearSelection
                            : () {
                                setState(() {
                                  _selectionMode = true;
                                  _selectedIds.clear();
                                });
                              },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PopupMenuButton<GigSortOption>(
                          onSelected: (value) {
                            ref.read(gigSortProvider.notifier).state = value;
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: GigSortOption.fechaAsc,
                              child: Text('Fecha (antigua)'),
                            ),
                            const PopupMenuItem(
                              value: GigSortOption.fechaDesc,
                              child: Text('Fecha (reciente)'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: GigSortOption.precioAsc,
                              child: Text('Precio (menor)'),
                            ),
                            const PopupMenuItem(
                              value: GigSortOption.precioDesc,
                              child: Text('Precio (mayor)'),
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
                            if (value == 'select_all') {
                              _toggleSelectAll(filteredGigs);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'select_all',
                              child: Text('Seleccionar todo'),
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
                ),

                // ── Fila 1: Chips de estado ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _StatusChip(
                          label: 'Todos',
                          selected: statusFilter == null,
                          onTap: () =>
                              ref.read(gigStatusFilterProvider.notifier).state =
                                  null,
                        ),
                        _StatusChip(
                          label: GigStatus.confirmado.label,
                          selected: statusFilter == GigStatus.confirmado,
                          onTap: () =>
                              ref.read(gigStatusFilterProvider.notifier).state =
                                  GigStatus.confirmado,
                        ),
                        _StatusChip(
                          label: GigStatus.facturado.label,
                          selected: statusFilter == GigStatus.facturado,
                          onTap: () =>
                              ref.read(gigStatusFilterProvider.notifier).state =
                                  GigStatus.facturado,
                        ),
                        _StatusChip(
                          label: GigStatus.cobrado.label,
                          selected: statusFilter == GigStatus.cobrado,
                          onTap: () =>
                              ref.read(gigStatusFilterProvider.notifier).state =
                                  GigStatus.cobrado,
                        ),
                        _StatusChip(
                          label: GigStatus.confirmadoB.label,
                          selected: statusFilter == GigStatus.confirmadoB,
                          onTap: () =>
                              ref.read(gigStatusFilterProvider.notifier).state =
                                  GigStatus.confirmadoB,
                        ),
                        _StatusChip(
                          label: GigStatus.realizadoB.label,
                          selected: statusFilter == GigStatus.realizadoB,
                          onTap: () =>
                              ref.read(gigStatusFilterProvider.notifier).state =
                                  GigStatus.realizadoB,
                        ),
                        _StatusChip(
                          label: GigStatus.cobradoB.label,
                          selected: statusFilter == GigStatus.cobradoB,
                          onTap: () =>
                              ref.read(gigStatusFilterProvider.notifier).state =
                                  GigStatus.cobradoB,
                        ),
                        _StatusChip(
                          label: GigStatus.cancelado.label,
                          selected: statusFilter == GigStatus.cancelado,
                          onTap: () =>
                              ref.read(gigStatusFilterProvider.notifier).state =
                                  GigStatus.cancelado,
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
                        _FilterButton(
                          icon: Icons.calendar_today,
                          label: selectedYear?.toString() ?? 'Año',
                          active: selectedYear != null,
                          onTap: () => _showYearSheet(context, ref, yearCounts),
                        ),
                        const SizedBox(width: 8),
                        _FilterButton(
                          icon: Icons.date_range,
                          label: monthLabel ?? 'Mes',
                          active: selectedMonth != null,
                          onTap: () =>
                              _showMonthSheet(context, ref, monthsWithData),
                        ),
                        const SizedBox(width: 8),
                        _FilterButton(
                          icon: Icons.person,
                          label: clientFilterName ?? 'Cliente',
                          active: clientFilter != null,
                          onTap: () => _showClientSheet(
                            context,
                            ref,
                            clients,
                            clientGigCounts,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _FilterButton(
                          icon: Icons.bolt,
                          label: facturableFilter == null
                              ? 'Facturable'
                              : facturableFilter == true
                              ? 'Facturable'
                              : 'En B',
                          active: facturableFilter != null,
                          onTap: () => _showFacturableSheet(context, ref),
                        ),
                        if (hasActiveFilters) ...[
                          const SizedBox(width: 8),
                          _ClearFiltersButton(
                            onTap: () => _clearAllFilters(ref),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Lista o empty state ──
                if (filteredGigs.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.music_off,
                            size: 64,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No hay bolos con estos filtros',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: filteredGigs.length,
                      itemBuilder: (context, index) {
                        final gig = filteredGigs[index];
                        return _GigListTile(
                          gig: gig,
                          selectionMode: _selectionMode,
                          selected: _selectedIds.contains(gig.id),
                          onLongPressSelect: () => _enterSelection(gig.id),
                          onToggleSelect: () => _toggleSelection(gig.id),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () =>
            Column(children: List.generate(6, (_) => const GigCardSkeleton())),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/gig/new'),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.nuevoBolo),
            ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: _selectionMode ? 62 : 0,
        child: _selectionMode
            ? SafeArea(
                top: false,
                child: Material(
                  color: AppColors.surface,
                  elevation: 8,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Cobrado',
                          onPressed: () => _applyBulkStatus(GigStatus.cobrado),
                          icon: const Icon(Icons.check_circle_outline),
                        ),
                        IconButton(
                          tooltip: 'Confirmado',
                          onPressed: () =>
                              _applyBulkStatus(GigStatus.confirmado),
                          icon: const Icon(Icons.hourglass_empty),
                        ),
                        IconButton(
                          tooltip: 'En B',
                          onPressed: () =>
                              _applyBulkStatus(GigStatus.cobradoB),
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Facturable',
                          onPressed: () => _applyBulkFacturable(true),
                          icon: const Icon(Icons.receipt_long_outlined),
                        ),
                        IconButton(
                          tooltip: 'No facturable',
                          onPressed: () => _applyBulkFacturable(false),
                          icon: const Icon(Icons.money_off_csred_outlined),
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          onPressed: () => _applyBulkDelete(context),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  // ─── Bottom sheets ───

  void _showYearSheet(
    BuildContext context,
    WidgetRef ref,
    Map<int, int> yearCounts,
  ) {
    final sortedYears = yearCounts.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final selectedYear = ref.read(gigYearFilterProvider);

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
                ref.read(gigYearFilterProvider.notifier).state = value;
                ref.read(gigMonthFilterProvider.notifier).state = null;
                Navigator.pop(ctx);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<int?>(
                    title: const Text('Todos los años'),
                    value: null,
                  ),
                  ...sortedYears.map(
                    (year) => RadioListTile<int?>(
                      title: Text(year.toString()),
                      subtitle: Text('${yearCounts[year]} bolos'),
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

  void _showMonthSheet(
    BuildContext context,
    WidgetRef ref,
    Map<int, int> monthsWithData,
  ) {
    final selectedMonth = ref.read(gigMonthFilterProvider);

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
                ref.read(gigMonthFilterProvider.notifier).state = null;
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
                          ref.read(gigMonthFilterProvider.notifier).state =
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

  void _showClientSheet(
    BuildContext context,
    WidgetRef ref,
    List<Client> clients,
    Map<String, int> gigCounts,
  ) {
    final clientsWithGigs =
        clients.where((c) => (gigCounts[c.id] ?? 0) > 0).toList()..sort(
          (a, b) => (gigCounts[b.id] ?? 0).compareTo(gigCounts[a.id] ?? 0),
        );

    final selectedClientId = ref.read(gigClientFilterProvider);

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
        builder: (context, scrollController) => _ClientSheetContent(
          clients: clientsWithGigs,
          gigCounts: gigCounts,
          selectedClientId: selectedClientId,
          scrollController: scrollController,
          onSelect: (clientId) {
            ref.read(gigClientFilterProvider.notifier).state = clientId;
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  void _showFacturableSheet(BuildContext context, WidgetRef ref) {
    final facturableFilter = ref.read(gigFacturableFilterProvider);

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
                'Filtrar por facturabilidad',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<bool?>(
              groupValue: facturableFilter,
              onChanged: (value) {
                ref.read(gigFacturableFilterProvider.notifier).state = value;
                Navigator.pop(ctx);
              },
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<bool?>(title: Text('Todos'), value: null),
                  RadioListTile<bool?>(
                    title: Text('Solo facturables'),
                    value: true,
                  ),
                  RadioListTile<bool?>(title: Text('Solo en B'), value: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets auxiliares ───

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.white : AppColors.textPrimary,
        ),
        selectedColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _FilterButton({
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

class _ClearFiltersButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ClearFiltersButton({required this.onTap});

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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: _InlineActionButtonContent(icon: icon, label: label),
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientSheetContent extends StatefulWidget {
  final List<Client> clients;
  final Map<String, int> gigCounts;
  final String? selectedClientId;
  final ScrollController scrollController;
  final ValueChanged<String?> onSelect;

  const _ClientSheetContent({
    required this.clients,
    required this.gigCounts,
    required this.selectedClientId,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  State<_ClientSheetContent> createState() => _ClientSheetContentState();
}

class _ClientSheetContentState extends State<_ClientSheetContent> {
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
            color: AppColors.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filtrar por cliente',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Buscar cliente...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RadioGroup<String?>(
            groupValue: widget.selectedClientId,
            onChanged: (value) => widget.onSelect(value),
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: filtered.length + 1, // +1 for "Todos"
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const RadioListTile<String?>(
                    title: Text('Todos los clientes'),
                    value: null,
                  );
                }
                final client = filtered[index - 1];
                final count = widget.gigCounts[client.id] ?? 0;
                return RadioListTile<String?>(
                  title: Text(client.nombre),
                  subtitle: Text('$count bolos'),
                  value: client.id,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _GigListTile extends ConsumerWidget {
  final Gig gig;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onLongPressSelect;
  final VoidCallback onToggleSelect;

  const _GigListTile({
    required this.gig,
    required this.selectionMode,
    required this.selected,
    required this.onLongPressSelect,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(gig.clientId));

    return Dismissible(
      key: Key(gig.id),
      direction: selectionMode
          ? DismissDirection.none
          : DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (selectionMode) return false;
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.mediumImpact();
          _showSwipeOptions(context, ref, gig);
          return false;
        } else {
          HapticFeedback.selectionClick();
          context.push('/gig/${gig.id}');
          return false;
        }
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_horiz, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text(
              'Opciones',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text(
              'Ver',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      child: Hero(
        tag: 'gig-${gig.id}',
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            onTap: () {
              if (selectionMode) {
                onToggleSelect();
                return;
              }
              AppHaptics.light();
              context.push('/gig/${gig.id}');
            },
            onLongPress: onLongPressSelect,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: gig.facturable
                    ? AppColors.primaryLight
                    : AppColors.purpleBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.music_note_outlined,
                color: gig.facturable ? AppColors.primary : AppColors.purple,
                size: 22,
              ),
            ),
            title: clientAsync.when(
              data: (client) => Text(
                client?.nombre ?? 'Cliente desconocido',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              loading: () => const Text('...'),
              error: (_, __) => const Text('Error'),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormatter.display(gig.fecha),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (gig.cachet != null)
                  Text(
                    CurrencyFormatter.format(gig.cachet!),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
            trailing: selectionMode
                ? Checkbox(value: selected, onChanged: (_) => onToggleSelect())
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      FacturableBadge(facturable: gig.facturable),
                      const SizedBox(height: 4),
                      StatusBadge(status: gig.status, facturable: gig.facturable),
                    ],
                  ),
            isThreeLine: true,
          ),
        ),
      ),
    );
  }

  void _showSwipeOptions(BuildContext context, WidgetRef ref, Gig gig) {
    showModalBottomSheet(
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
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit, color: AppColors.primary),
                title: const Text('Editar bolo'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/gig/edit/${gig.id}');
                },
              ),
              if (gig.facturable &&
                  (gig.invoiceId == null || gig.invoiceId!.isEmpty))
                ListTile(
                  leading: const Icon(
                    Icons.receipt_long,
                    color: AppColors.success,
                  ),
                  title: const Text('Generar factura'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/invoice/new/${gig.id}');
                  },
                ),
              if (gig.invoiceId != null && gig.invoiceId!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.receipt, color: AppColors.success),
                  title: const Text('Ver factura'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/invoice/${gig.invoiceId}');
                  },
                ),
              ListTile(
                leading: const Icon(Icons.cancel, color: AppColors.warning),
                title: const Text('Marcar como cancelado'),
                onTap: () {
                  AppHaptics.medium();
                  Navigator.pop(ctx);
                  ref
                      .read(gigsProvider.notifier)
                      .updateGig(gig.copyWith(status: GigStatus.cancelado));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
