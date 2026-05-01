import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/gig.dart';
import '../../models/client.dart';
import '../../models/invoice.dart';
import '../../providers/gig_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/facturable_badge.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

final _selectedDayProvider = StateProvider<DateTime?>((ref) => null);
final _focusedDayProvider = StateProvider<DateTime>((ref) => DateTime.now());
final _syncingProvider = StateProvider<bool>((ref) => false);
final _viewModeProvider = StateProvider<bool>(
  (ref) => true,
); // true = calendario, false = lista

// ─── Filtros vista lista ───
final _statusFilterProvider = StateProvider<GigStatus?>((ref) => null);
final _yearFilterProvider = StateProvider<int?>((ref) => null);
final _monthFilterProvider = StateProvider<int?>((ref) => null);
final _clientFilterProvider = StateProvider<String?>((ref) => null);
final _facturableFilterProvider = StateProvider<bool?>((ref) => null);
final _selectionModeProvider = StateProvider<bool>((ref) => false);
final _selectedGigIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

// Ordenación
enum GigSortOption {
  fechaDesc,
  fechaAsc,
  clienteAsc,
  clienteDesc,
  precioDesc,
  precioAsc,
}

final _gigSortProvider = StateProvider<GigSortOption>(
  (ref) => GigSortOption.fechaDesc,
);

void _clearAllListFilters(WidgetRef ref) {
  ref.read(_statusFilterProvider.notifier).state = null;
  ref.read(_yearFilterProvider.notifier).state = null;
  ref.read(_monthFilterProvider.notifier).state = null;
  ref.read(_clientFilterProvider.notifier).state = null;
  ref.read(_facturableFilterProvider.notifier).state = null;
}

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  Color _markerColor(Gig gig) {
    if (gig.status == GigStatus.cancelado) return AppColors.error;
    if (gig.status == GigStatus.pagado || gig.status == GigStatus.cobradoEnB) {
      return AppColors.success;
    }
    if (gig.status == GigStatus.facturaEnviada) return AppColors.warning;
    if (!gig.facturable) return AppColors.purple;
    return AppColors.primary;
  }

  Future<void> _syncToGoogleCalendar(WidgetRef ref, List<Gig> gigs) async {
    ref.read(_syncingProvider.notifier).state = true;
    try {
      final service = GoogleCalendarService();
      for (final gig in gigs) {
        final client = await ref.read(clientByIdProvider(gig.clientId).future);
        await service.syncGig(
          gig: gig,
          clientName: client?.nombre ?? 'Cliente',
          cachet: gig.cachet,
        );
      }
    } finally {
      ref.read(_syncingProvider.notifier).state = false;
    }
  }

  /// Repara estados de bolos según sus facturas vinculadas.
  Future<void> _repairGigStatuses(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final gigs = ref.read(gigsProvider).valueOrNull ?? [];
    final allInvoices = ref.read(invoicesProvider).valueOrNull ?? [];
    int repaired = 0;

    // Crear mapa de facturas por gigId para buscar rápido
    final invoiceByGig = <String, Invoice>{};
    for (final inv in allInvoices) {
      invoiceByGig[inv.gigId] = inv;
    }

    for (final gig in gigs) {
      if (gig.invoiceId == null) continue;

      final invoice = invoiceByGig[gig.id];
      if (invoice == null) continue;

      GigStatus expectedStatus;
      switch (invoice.status) {
        case InvoiceStatus.pagada:
          expectedStatus = GigStatus.pagado;
          break;
        case InvoiceStatus.enviada:
          expectedStatus = GigStatus.facturaEnviada;
          break;
        case InvoiceStatus.borrador:
          expectedStatus = GigStatus.facturaGenerada;
          break;
      }

      if (gig.status != expectedStatus) {
        await ref
            .read(gigsProvider.notifier)
            .updateStatus(gig.id, expectedStatus);
        repaired++;
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          repaired > 0
              ? '$repaired bolos reparados'
              : 'Todos los bolos están sincronizados',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gigsAsync = ref.watch(gigsProvider);
    final selectedDay = ref.watch(_selectedDayProvider);
    final focusedDay = ref.watch(_focusedDayProvider);
    final googleAuth = ref.watch(googleAuthProvider);
    final syncing = ref.watch(_syncingProvider);
    final isCalendarView = ref.watch(_viewModeProvider);
    final selectionMode = ref.watch(_selectionModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isCalendarView ? AppStrings.calendario : 'Bolos',
        ),
        actions: [
          // Toggle vista
          IconButton(
            icon: Icon(isCalendarView ? Icons.list : Icons.calendar_month),
            tooltip: isCalendarView ? 'Ver como lista' : 'Ver calendario',
            onPressed: () {
              ref.read(_viewModeProvider.notifier).state = !isCalendarView;
            },
          ),
          if (googleAuth.isSignedIn && isCalendarView)
            syncing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: 'Sincronizar con Google Calendar',
                    onPressed: () {
                      final gigs = gigsAsync.valueOrNull;
                      if (gigs != null) _syncToGoogleCalendar(ref, gigs);
                    },
                  ),
          if (!isCalendarView)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'repair') {
                  await _repairGigStatuses(context, ref);
                } else {
                  // Sort option
                  final option = GigSortOption.values.where(
                    (o) => o.name == value,
                  );
                  if (option.isNotEmpty) {
                    ref.read(_gigSortProvider.notifier).state = option.first;
                  }
                }
              },
              itemBuilder: (context) {
                final sortOption = ref.read(_gigSortProvider);
                return [
                  ..._sortMenuItems(sortOption),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'repair',
                    child: Row(
                      children: [
                        Icon(Icons.build, size: 20),
                        SizedBox(width: 12),
                        Text('Reparar estados'),
                      ],
                    ),
                  ),
                ];
              },
            ),
        ],
      ),
      body: isCalendarView
          ? _buildCalendarView(
              context,
              ref,
              gigsAsync,
              selectedDay,
              focusedDay,
              googleAuth,
            )
          : _buildListView(context, ref, gigsAsync),
      floatingActionButton: selectionMode
          ? null
          : FloatingActionButton(
              onPressed: () => context.push('/gig/new'),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildCalendarView(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Gig>> gigsAsync,
    DateTime? selectedDay,
    DateTime focusedDay,
    GoogleAuthState googleAuth,
  ) {
    return gigsAsync.when(
      data: (gigs) {
        final events = <DateTime, List<Gig>>{};
        for (final gig in gigs) {
          final key = DateTime(gig.fecha.year, gig.fecha.month, gig.fecha.day);
          events.putIfAbsent(key, () => []).add(gig);
        }

        List<Gig> getEventsForDay(DateTime day) {
          return events[DateTime(day.year, day.month, day.day)] ?? [];
        }

        final selectedGigs = selectedDay != null
            ? getEventsForDay(selectedDay)
            : <Gig>[];

        return Column(
          children: [
            // Banner Google Sign-In
            if (!googleAuth.isSignedIn)
              _GoogleSignInBanner()
            else
              _GoogleAccountBanner(
                email: googleAuth.email ?? '',
                displayName: googleAuth.displayName,
              ),

            TableCalendar<Gig>(
              firstDay: DateTime(2020),
              lastDay: DateTime(2030),
              focusedDay: focusedDay,
              selectedDayPredicate: (day) => isSameDay(selectedDay, day),
              eventLoader: getEventsForDay,
              locale: 'es_ES',
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                markersMaxCount: 3,
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  if (events.isEmpty) return null;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: events.take(3).map((gig) {
                      return Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: _markerColor(gig),
                          shape: BoxShape.circle,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              onDaySelected: (selected, focused) {
                ref.read(_selectedDayProvider.notifier).state = selected;
                ref.read(_focusedDayProvider.notifier).state = focused;
              },
              onPageChanged: (focused) {
                ref.read(_focusedDayProvider.notifier).state = focused;
              },
            ),

            // Leyenda
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _LegendItem(
                    color: AppColors.primary,
                    label: 'Pendiente facturable',
                  ),
                  _LegendItem(
                    color: AppColors.accentPurple,
                    label: 'Pendiente no facturable',
                  ),
                  _LegendItem(
                    color: AppColors.accentOrange,
                    label: 'Pdte cobro',
                  ),
                  _LegendItem(color: AppColors.accentGreen, label: 'Cobrado'),
                  _LegendItem(color: AppColors.accentRed, label: 'Cancelado'),
                ],
              ),
            ),

            const Divider(),

            // Bolos del día seleccionado
            Expanded(
              child: selectedGigs.isEmpty
                  ? const Center(
                      child: Text(
                        'Selecciona un día para ver los bolos',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: selectedGigs.length,
                      itemBuilder: (context, index) {
                        final gig = selectedGigs[index];
                        return _CalendarGigTile(gig: gig);
                      },
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildListView(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Gig>> gigsAsync,
  ) {
    final statusFilter = ref.watch(_statusFilterProvider);
    final selectedYear = ref.watch(_yearFilterProvider);
    final selectedMonth = ref.watch(_monthFilterProvider);
    final clientFilter = ref.watch(_clientFilterProvider);
    final facturableFilter = ref.watch(_facturableFilterProvider);
    final sortOption = ref.watch(_gigSortProvider);
    final clientsAsync = ref.watch(clientsProvider);
    final selectionMode = ref.watch(_selectionModeProvider);
    final selectedGigIds = ref.watch(_selectedGigIdsProvider);

    final hasActiveFilters =
        statusFilter != null ||
        selectedYear != null ||
        selectedMonth != null ||
        clientFilter != null ||
        facturableFilter != null;

    return gigsAsync.when(
      data: (allGigs) {
        final clients = clientsAsync.valueOrNull ?? [];
        final clientMap = {for (final c in clients) c.id: c};

        final totalCount = allGigs.length;

        // Aplicar filtros
        final filteredGigs = allGigs.where((gig) {
          if (statusFilter != null && gig.status != statusFilter) return false;
          if (selectedYear != null && gig.fecha.year != selectedYear) {
            return false;
          }
          if (selectedMonth != null && gig.fecha.month != selectedMonth) {
            return false;
          }
          if (clientFilter != null && gig.clientId != clientFilter) {
            return false;
          }
          if (facturableFilter != null && gig.facturable != facturableFilter) {
            return false;
          }
          return true;
        }).toList();

        // Aplicar ordenación
        filteredGigs.sort((a, b) {
          switch (sortOption) {
            case GigSortOption.fechaDesc:
              return b.fecha.compareTo(a.fecha);
            case GigSortOption.fechaAsc:
              return a.fecha.compareTo(b.fecha);
            case GigSortOption.clienteAsc:
              final clientA = clientMap[a.clientId]?.alias ?? '';
              final clientB = clientMap[b.clientId]?.alias ?? '';
              return clientA.toLowerCase().compareTo(clientB.toLowerCase());
            case GigSortOption.clienteDesc:
              final clientA = clientMap[a.clientId]?.alias ?? '';
              final clientB = clientMap[b.clientId]?.alias ?? '';
              return clientB.toLowerCase().compareTo(clientA.toLowerCase());
            case GigSortOption.precioDesc:
              return (b.cachet ?? 0).compareTo(a.cachet ?? 0);
            case GigSortOption.precioAsc:
              return (a.cachet ?? 0).compareTo(b.cachet ?? 0);
          }
        });

        final filteredCount = filteredGigs.length;
        final filteredCachet = filteredGigs.fold<double>(
          0,
          (sum, g) => sum + (g.cachet ?? 0),
        );

        // Conteos por año
        final yearCounts = <int, int>{};
        for (final gig in allGigs) {
          yearCounts[gig.fecha.year] = (yearCounts[gig.fecha.year] ?? 0) + 1;
        }

        // Meses con datos
        final monthsWithData = <int, int>{};
        if (selectedYear != null) {
          for (final gig in allGigs) {
            if (gig.fecha.year == selectedYear) {
              monthsWithData[gig.fecha.month] =
                  (monthsWithData[gig.fecha.month] ?? 0) + 1;
            }
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
          final m = DateFormat.MMM('es').format(DateTime(2024, selectedMonth));
          monthLabel = m[0].toUpperCase() + m.substring(1);
        }

        return Column(
          children: [
            if (selectionMode) _buildGigsSelectionHeader(context, ref),
            // ── Resumen dinámico ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    style: TextStyle(fontSize: 16, color: AppColors.primary),
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
                    label: selectionMode ? 'Cancelar' : 'Seleccionar',
                    onTap: () {
                      if (selectionMode) {
                        ref.read(_selectionModeProvider.notifier).state = false;
                        ref.read(_selectedGigIdsProvider.notifier).state =
                            <String>{};
                      } else {
                        ref.read(_selectionModeProvider.notifier).state = true;
                        ref.read(_selectedGigIdsProvider.notifier).state =
                            <String>{};
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PopupMenuButton<String>(
                      onSelected: (value) {
                        final option = GigSortOption.values.where(
                          (o) => o.name == value,
                        );
                        if (option.isNotEmpty) {
                          ref.read(_gigSortProvider.notifier).state =
                              option.first;
                        }
                      },
                      itemBuilder: (context) => _sortMenuItems(sortOption),
                      child: const _InlineActionButtonContent(
                        icon: Icons.sort,
                        label: 'Ordenar',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PopupMenuButton<String>(
                      enabled: !selectionMode || selectedGigIds.isNotEmpty,
                      onSelected: (value) {
                        if (value == 'select_all') {
                          ref.read(_selectionModeProvider.notifier).state =
                              true;
                          ref.read(_selectedGigIdsProvider.notifier).state =
                              filteredGigs.map((g) => g.id).toSet();
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
                          ref.read(_statusFilterProvider.notifier).state = null,
                    ),
                    _StatusChip(
                      label: GigStatus.pendiente.label,
                      selected: statusFilter == GigStatus.pendiente,
                      onTap: () =>
                          ref.read(_statusFilterProvider.notifier).state =
                              GigStatus.pendiente,
                    ),
                    _StatusChip(
                      label: GigStatus.facturaEnviada.label,
                      selected: statusFilter == GigStatus.facturaEnviada,
                      onTap: () =>
                          ref.read(_statusFilterProvider.notifier).state =
                              GigStatus.facturaEnviada,
                    ),
                    _StatusChip(
                      label: GigStatus.pagado.label,
                      selected: statusFilter == GigStatus.pagado,
                      onTap: () =>
                          ref.read(_statusFilterProvider.notifier).state =
                              GigStatus.pagado,
                    ),
                    _StatusChip(
                      label: GigStatus.cobradoEnB.label,
                      selected: statusFilter == GigStatus.cobradoEnB,
                      onTap: () =>
                          ref.read(_statusFilterProvider.notifier).state =
                              GigStatus.cobradoEnB,
                    ),
                    _StatusChip(
                      label: GigStatus.cancelado.label,
                      selected: statusFilter == GigStatus.cancelado,
                      onTap: () =>
                          ref.read(_statusFilterProvider.notifier).state =
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
                      onTap: selectedYear != null
                          ? () => _showMonthSheet(context, ref, monthsWithData)
                          : null,
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
                        onTap: () => _clearAllListFilters(ref),
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
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
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
                      selectionMode: selectionMode,
                      isSelected: selectedGigIds.contains(gig.id),
                      onToggle: () {
                        final current = ref.read(_selectedGigIdsProvider);
                        final updated = {...current};
                        if (updated.contains(gig.id)) {
                          updated.remove(gig.id);
                        } else {
                          updated.add(gig.id);
                        }
                        ref.read(_selectedGigIdsProvider.notifier).state =
                            updated;
                      },
                      onLongSelect: () {},
                    );
                  },
                ),
              ),
            if (selectionMode)
              _BulkGigsActionsBar(
                selectedIds: selectedGigIds,
                onDone: () {
                  ref.read(_selectionModeProvider.notifier).state = false;
                  ref.read(_selectedGigIdsProvider.notifier).state = <String>{};
                },
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildGigsSelectionHeader(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_selectedGigIdsProvider);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () {
              ref.read(_selectedGigIdsProvider.notifier).state = <String>{};
              ref.read(_selectionModeProvider.notifier).state = false;
            },
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('Deseleccionar'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              '${selected.length} seleccionados',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
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
    final selectedYear = ref.read(_yearFilterProvider);

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
                ref.read(_yearFilterProvider.notifier).state = value;
                ref.read(_monthFilterProvider.notifier).state = null;
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
    final selectedMonth = ref.read(_monthFilterProvider);

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
                ref.read(_monthFilterProvider.notifier).state = null;
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
                          ref.read(_monthFilterProvider.notifier).state = month;
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

    final selectedClientId = ref.read(_clientFilterProvider);

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
            ref.read(_clientFilterProvider.notifier).state = clientId;
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  void _showFacturableSheet(BuildContext context, WidgetRef ref) {
    final facturableFilter = ref.read(_facturableFilterProvider);

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
                ref.read(_facturableFilterProvider.notifier).state = value;
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

  List<PopupMenuEntry<String>> _sortMenuItems(GigSortOption current) {
    Widget buildItem(GigSortOption option, String label, IconData icon) {
      final isSelected = current == option;
      return PopupMenuItem<String>(
        value: option.name,
        onTap: () => {},
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
              const Icon(Icons.check, size: 18, color: AppColors.primary),
            ],
          ],
        ),
      );
    }

    return [
      buildItem(
            GigSortOption.fechaDesc,
            'Fecha (reciente)',
            Icons.arrow_downward,
          )
          as PopupMenuEntry<String>,
      buildItem(GigSortOption.fechaAsc, 'Fecha (antigua)', Icons.arrow_upward)
          as PopupMenuEntry<String>,
      const PopupMenuDivider(),
      buildItem(GigSortOption.clienteAsc, 'Cliente (A-Z)', Icons.sort_by_alpha)
          as PopupMenuEntry<String>,
      buildItem(GigSortOption.clienteDesc, 'Cliente (Z-A)', Icons.sort_by_alpha)
          as PopupMenuEntry<String>,
      const PopupMenuDivider(),
      buildItem(
            GigSortOption.precioDesc,
            'Precio (mayor)',
            Icons.arrow_downward,
          )
          as PopupMenuEntry<String>,
      buildItem(GigSortOption.precioAsc, 'Precio (menor)', Icons.arrow_upward)
          as PopupMenuEntry<String>,
    ];
  }
}

// ─── Widgets auxiliares para filtros ───

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
    final bgColor = active ? AppColors.warningBg : AppColors.surface;
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
              itemCount: filtered.length + 1,
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
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onLongSelect;

  const _GigListTile({
    required this.gig,
    required this.selectionMode,
    required this.isSelected,
    required this.onToggle,
    required this.onLongSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(gig.clientId));

    return Card(
      color: isSelected ? AppColors.primaryLight : null,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.cardBorder,
          width: isSelected ? 1.1 : 0.8,
        ),
      ),
      child: InkWell(
        onTap: selectionMode ? onToggle : () => context.push('/gig/${gig.id}'),
        onLongPress: selectionMode ? null : onLongSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selectionMode) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggle(),
                  activeColor: AppColors.primary,
                ),
                const SizedBox(width: 8),
              ],
              Container(
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    clientAsync.when(
                      data: (client) => Text(
                        client?.alias.isNotEmpty == true
                            ? client!.alias
                            : client?.nombre ?? 'Cliente desconocido',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0D1B2A),
                        ),
                      ),
                      loading: () => const Text('...'),
                      error: (_, __) => const Text('Error'),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${DateFormatter.dayOfWeekFull(gig.fecha)}${gig.cachet != null ? ' · ${CurrencyFormatter.format(gig.cachet!)}' : ''}',
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8C95A6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        FacturableBadge(facturable: gig.facturable),
                        const SizedBox(width: 6),
                        StatusBadge(status: gig.status),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkGigsActionsBar extends ConsumerWidget {
  final Set<String> selectedIds;
  final VoidCallback onDone;

  const _BulkGigsActionsBar({required this.selectedIds, required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> setStatus(GigStatus status) async {
      await ref
          .read(gigsProvider.notifier)
          .bulkUpdateStatus(selectedIds, status);
      onDone();
    }

    Future<void> setFacturable(bool value) async {
      await ref
          .read(gigsProvider.notifier)
          .bulkSetFacturable(selectedIds, value);
      onDone();
    }

    Future<void> removeAll() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Eliminar bolos'),
          content: Text('Se eliminarán ${selectedIds.length} bolos.'),
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
      if (ok == true) {
        try {
          await ref.read(gigsProvider.notifier).bulkDelete(selectedIds);
          onDone();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No se pudo eliminar en lote: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      }
    }

    return Container(
      height: 84,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _BulkActionButton(
              icon: Icons.check_circle_outline,
              label: 'Cobrar',
              fgColor: AppColors.success,
              bgColor: AppColors.successBg,
              onTap: () => setStatus(GigStatus.pagado),
            ),
            const SizedBox(width: 8),
            _BulkActionButton(
              icon: Icons.hourglass_empty,
              label: 'Pendiente',
              fgColor: AppColors.primary,
              bgColor: AppColors.primaryLight,
              onTap: () => setStatus(GigStatus.pendiente),
            ),
            const SizedBox(width: 8),
            _BulkActionButton(
              icon: Icons.schedule,
              label: 'Pdte cobro',
              fgColor: AppColors.warning,
              bgColor: AppColors.warningBg,
              onTap: () => setStatus(GigStatus.facturaEnviada),
            ),
            const SizedBox(width: 8),
            _BulkActionButton(
              icon: Icons.receipt_long_outlined,
              label: 'Facturable',
              fgColor: AppColors.primary,
              bgColor: AppColors.primaryLight,
              onTap: () => setFacturable(true),
            ),
            const SizedBox(width: 8),
            _BulkActionButton(
              icon: Icons.payments_outlined,
              label: 'En B',
              fgColor: AppColors.purple,
              bgColor: AppColors.purpleBg,
              onTap: () => setFacturable(false),
            ),
            const SizedBox(width: 8),
            _BulkActionButton(
              icon: Icons.delete_outline,
              label: 'Eliminar',
              fgColor: AppColors.error,
              bgColor: AppColors.errorBg,
              onTap: removeAll,
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color fgColor;
  final Color bgColor;
  final VoidCallback onTap;

  const _BulkActionButton({
    required this.icon,
    required this.label,
    required this.fgColor,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fgColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fgColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fgColor,
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _CalendarGigTile extends ConsumerWidget {
  final Gig gig;
  const _CalendarGigTile({required this.gig});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(gig.clientId));

    return Card(
      child: ListTile(
        onTap: () => context.push('/gig/${gig.id}'),
        title: clientAsync.when(
          data: (c) =>
              Text(c?.alias.isNotEmpty == true ? c!.alias : c?.nombre ?? ''),
          loading: () => const Text('...'),
          error: (_, __) => const Text('Error'),
        ),
        subtitle: gig.cachet != null
            ? Text(CurrencyFormatter.format(gig.cachet!))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FacturableBadge(facturable: gig.facturable),
            const SizedBox(width: 4),
            StatusBadge(status: gig.status),
          ],
        ),
      ),
    );
  }
}

class _GoogleSignInBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.calendar_month, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Conecta Google Calendar para sincronizar tus bolos',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.login, size: 16),
            label: const Text('Conectar', style: TextStyle(fontSize: 12)),
            onPressed: () => ref.read(googleAuthProvider.notifier).signIn(),
          ),
        ],
      ),
    );
  }
}

class _GoogleAccountBanner extends StatelessWidget {
  final String email;
  final String? displayName;

  const _GoogleAccountBanner({required this.email, this.displayName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.accentGreen.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            size: 16,
            color: AppColors.accentGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayName != null ? '$displayName • $email' : email,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.sync, size: 14, color: AppColors.accentGreen),
          const SizedBox(width: 4),
          const Text(
            'Google Calendar',
            style: TextStyle(fontSize: 11, color: AppColors.accentGreen),
          ),
        ],
      ),
    );
  }
}
