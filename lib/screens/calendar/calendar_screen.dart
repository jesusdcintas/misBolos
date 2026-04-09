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

final _selectedDayProvider = StateProvider<DateTime?>((ref) => null);
final _focusedDayProvider = StateProvider<DateTime>((ref) => DateTime.now());
final _syncingProvider = StateProvider<bool>((ref) => false);
final _viewModeProvider = StateProvider<bool>((ref) => true); // true = calendario, false = lista

// Filtro para la vista lista
enum GigListFilter { todos, pagados, noPagados }
final _gigListFilterProvider = StateProvider<GigListFilter>((ref) => GigListFilter.todos);

// Ordenación para la vista lista
enum GigSortOption { fechaDesc, fechaAsc, clienteAsc, clienteDesc, precioDesc, precioAsc }
final _gigSortProvider = StateProvider<GigSortOption>((ref) => GigSortOption.fechaDesc);

// Cache de clientes para ordenar por nombre
final _clientsCacheProvider = FutureProvider<Map<String, Client>>((ref) async {
  final clientsAsync = ref.watch(clientsProvider);
  return clientsAsync.maybeWhen(
    data: (clients) => {for (var c in clients) c.id: c},
    orElse: () => <String, Client>{},
  );
});

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
        await ref.read(gigsProvider.notifier).updateStatus(gig.id, expectedStatus);
        repaired++;
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(repaired > 0
            ? '$repaired bolos reparados'
            : 'Todos los bolos están sincronizados'),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(isCalendarView ? AppStrings.calendario : 'Bolos'),
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
            PopupMenuButton<GigListFilter>(
              icon: const Icon(Icons.filter_list),
              tooltip: 'Filtrar',
              onSelected: (value) {
                ref.read(_gigListFilterProvider.notifier).state = value;
              },
              itemBuilder: (context) {
                final filter = ref.read(_gigListFilterProvider);
                return [
                  PopupMenuItem(
                    value: GigListFilter.todos,
                    child: Row(
                      children: [
                        Icon(Icons.all_inclusive,
                            color: filter == GigListFilter.todos
                                ? AppColors.primary
                                : AppColors.textSecondary),
                        const SizedBox(width: 12),
                        Text('Todos',
                            style: TextStyle(
                                fontWeight: filter == GigListFilter.todos
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: GigListFilter.pagados,
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: filter == GigListFilter.pagados
                                ? AppColors.success
                                : AppColors.textSecondary),
                        const SizedBox(width: 12),
                        Text('Pagados',
                            style: TextStyle(
                                fontWeight: filter == GigListFilter.pagados
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: GigListFilter.noPagados,
                    child: Row(
                      children: [
                        Icon(Icons.pending,
                            color: filter == GigListFilter.noPagados
                                ? AppColors.warning
                                : AppColors.textSecondary),
                        const SizedBox(width: 12),
                        Text('No pagados',
                            style: TextStyle(
                                fontWeight: filter == GigListFilter.noPagados
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ],
                    ),
                  ),
                ];
              },
            ),
          if (!isCalendarView)
            PopupMenuButton<GigSortOption>(
              icon: const Icon(Icons.sort),
              tooltip: 'Ordenar',
              onSelected: (value) {
                ref.read(_gigSortProvider.notifier).state = value;
              },
              itemBuilder: (context) {
                final sortOption = ref.read(_gigSortProvider);
                return [
                  _buildSortMenuItem(context, sortOption, GigSortOption.fechaDesc, 'Fecha (reciente)', Icons.arrow_downward),
                  _buildSortMenuItem(context, sortOption, GigSortOption.fechaAsc, 'Fecha (antigua)', Icons.arrow_upward),
                  const PopupMenuDivider(),
                  _buildSortMenuItem(context, sortOption, GigSortOption.clienteAsc, 'Cliente (A-Z)', Icons.sort_by_alpha),
                  _buildSortMenuItem(context, sortOption, GigSortOption.clienteDesc, 'Cliente (Z-A)', Icons.sort_by_alpha),
                  const PopupMenuDivider(),
                  _buildSortMenuItem(context, sortOption, GigSortOption.precioDesc, 'Precio (mayor)', Icons.arrow_downward),
                  _buildSortMenuItem(context, sortOption, GigSortOption.precioAsc, 'Precio (menor)', Icons.arrow_upward),
                ];
              },
            ),
          if (!isCalendarView)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'repair') {
                  await _repairGigStatuses(context, ref);
                }
              },
              itemBuilder: (context) => [
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
              ],
            ),
        ],
      ),
      body: isCalendarView
          ? _buildCalendarView(context, ref, gigsAsync, selectedDay, focusedDay, googleAuth)
          : _buildListView(context, ref, gigsAsync),
      floatingActionButton: FloatingActionButton(
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
                    _LegendItem(color: AppColors.primary, label: 'Pendiente facturable'),
                    _LegendItem(color: AppColors.accentPurple, label: 'Pendiente no facturable'),
                    _LegendItem(color: AppColors.accentOrange, label: 'Factura enviada'),
                    _LegendItem(color: AppColors.accentGreen, label: 'Pagado / Cobrado'),
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
    final filter = ref.watch(_gigListFilterProvider);
    final sortOption = ref.watch(_gigSortProvider);
    final clientsCacheAsync = ref.watch(_clientsCacheProvider);
    
    return clientsCacheAsync.when(
      data: (clientsMap) => gigsAsync.when(
        data: (gigs) {
          // Aplicar filtro
          final filteredGigs = gigs.where((gig) {
            switch (filter) {
              case GigListFilter.todos:
                return true;
              case GigListFilter.pagados:
                return gig.status == GigStatus.pagado ||
                    gig.status == GigStatus.cobradoEnB;
              case GigListFilter.noPagados:
                return gig.status != GigStatus.pagado &&
                    gig.status != GigStatus.cobradoEnB &&
                    gig.status != GigStatus.cancelado;
            }
          }).toList();

          // Aplicar ordenación
          filteredGigs.sort((a, b) {
            switch (sortOption) {
              case GigSortOption.fechaDesc:
                return b.fecha.compareTo(a.fecha);
              case GigSortOption.fechaAsc:
                return a.fecha.compareTo(b.fecha);
              case GigSortOption.clienteAsc:
                final clientA = clientsMap[a.clientId]?.alias ?? '';
                final clientB = clientsMap[b.clientId]?.alias ?? '';
                return clientA.toLowerCase().compareTo(clientB.toLowerCase());
              case GigSortOption.clienteDesc:
                final clientA = clientsMap[a.clientId]?.alias ?? '';
                final clientB = clientsMap[b.clientId]?.alias ?? '';
                return clientB.toLowerCase().compareTo(clientA.toLowerCase());
              case GigSortOption.precioDesc:
                return (b.cachet ?? 0).compareTo(a.cachet ?? 0);
              case GigSortOption.precioAsc:
                return (a.cachet ?? 0).compareTo(b.cachet ?? 0);
            }
          });

          if (filteredGigs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.music_off,
                    size: 64,
                    color: AppColors.textSecondary.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    filter == GigListFilter.todos
                        ? 'No hay bolos'
                        : filter == GigListFilter.pagados
                            ? 'No hay bolos pagados'
                            : 'No hay bolos pendientes de pago',
                    style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Calcular totales
        double totalCachet = 0;
        for (final gig in filteredGigs) {
          totalCachet += gig.cachet ?? 0;
        }

        return Column(
          children: [
            // Resumen
            Container(
              padding: const EdgeInsets.all(16),
              color: AppColors.primaryLight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryItem(
                    label: 'Bolos',
                    value: filteredGigs.length.toString(),
                    icon: Icons.music_note,
                  ),
                  _SummaryItem(
                    label: 'Total',
                    value: CurrencyFormatter.format(totalCachet),
                    icon: Icons.euro,
                  ),
                ],
              ),
            ),
            // Chip de filtro activo
            if (filter != GigListFilter.todos)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Chip(
                      label: Text(
                        filter == GigListFilter.pagados ? 'Pagados' : 'No pagados',
                      ),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        ref.read(_gigListFilterProvider.notifier).state =
                            GigListFilter.todos;
                      },
                      backgroundColor: filter == GigListFilter.pagados
                          ? AppColors.successBg
                          : AppColors.warningBg,
                      labelStyle: TextStyle(
                        color: filter == GigListFilter.pagados
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            // Lista
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: filteredGigs.length,
                itemBuilder: (context, index) {
                  final gig = filteredGigs[index];
                  return _GigListTile(gig: gig);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  PopupMenuItem<GigSortOption> _buildSortMenuItem(
    BuildContext context,
    GigSortOption current,
    GigSortOption option,
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

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _GigListTile extends ConsumerWidget {
  final Gig gig;

  const _GigListTile({required this.gig});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(gig.clientId));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context.push('/gig/${gig.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: gig.facturable ? AppColors.primaryLight : AppColors.purpleBg,
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
                        client?.alias.isNotEmpty == true ? client!.alias : client?.nombre ?? 'Cliente desconocido',
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
          data: (c) => Text(c?.alias.isNotEmpty == true ? c!.alias : c?.nombre ?? ''),
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

  const _GoogleAccountBanner({
    required this.email,
    this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.accentGreen.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 16, color: AppColors.accentGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayName != null ? '$displayName • $email' : email,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
