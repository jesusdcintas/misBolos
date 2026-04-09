import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/gig.dart';
import '../../providers/gig_provider.dart';
import '../../providers/client_provider.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/facturable_badge.dart';

enum GigFilter { todos, pagados, noPagados }

final gigFilterProvider = StateProvider<GigFilter>((ref) => GigFilter.todos);

class GigsListScreen extends ConsumerWidget {
  const GigsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gigsAsync = ref.watch(gigsProvider);
    final filter = ref.watch(gigFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bolos'),
        actions: [
          PopupMenuButton<GigFilter>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar',
            onSelected: (value) {
              ref.read(gigFilterProvider.notifier).state = value;
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: GigFilter.todos,
                child: Row(
                  children: [
                    Icon(
                      Icons.all_inclusive,
                      color: filter == GigFilter.todos
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Todos',
                      style: TextStyle(
                        fontWeight: filter == GigFilter.todos
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: GigFilter.pagados,
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: filter == GigFilter.pagados
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Pagados',
                      style: TextStyle(
                        fontWeight: filter == GigFilter.pagados
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: GigFilter.noPagados,
                child: Row(
                  children: [
                    Icon(
                      Icons.pending,
                      color: filter == GigFilter.noPagados
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'No pagados',
                      style: TextStyle(
                        fontWeight: filter == GigFilter.noPagados
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: gigsAsync.when(
        data: (gigs) {
          // Aplicar filtro
          final filteredGigs = gigs.where((gig) {
            switch (filter) {
              case GigFilter.todos:
                return true;
              case GigFilter.pagados:
                return gig.status == GigStatus.pagado ||
                    gig.status == GigStatus.cobradoEnB;
              case GigFilter.noPagados:
                return gig.status != GigStatus.pagado &&
                    gig.status != GigStatus.cobradoEnB &&
                    gig.status != GigStatus.cancelado;
            }
          }).toList();

          // Ordenar por fecha descendente
          filteredGigs.sort((a, b) => b.fecha.compareTo(a.fecha));

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
                    filter == GigFilter.todos
                        ? 'No hay bolos'
                        : filter == GigFilter.pagados
                            ? 'No hay bolos pagados'
                            : 'No hay bolos pendientes de pago',
                    style: TextStyle(
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
          int count = filteredGigs.length;
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
                      value: count.toString(),
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
              if (filter != GigFilter.todos)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Chip(
                        label: Text(
                          filter == GigFilter.pagados ? 'Pagados' : 'No pagados',
                        ),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () {
                          ref.read(gigFilterProvider.notifier).state =
                              GigFilter.todos;
                        },
                        backgroundColor: filter == GigFilter.pagados
                            ? AppColors.successBg
                            : AppColors.warningBg,
                        labelStyle: TextStyle(
                          color: filter == GigFilter.pagados
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/gig/new'),
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.nuevoBolo),
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
          style: TextStyle(
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
      child: ListTile(
        onTap: () => context.push('/gig/${gig.id}'),
        leading: Container(
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
              style: TextStyle(
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
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FacturableBadge(facturable: gig.facturable),
            const SizedBox(height: 4),
            StatusBadge(status: gig.status),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
