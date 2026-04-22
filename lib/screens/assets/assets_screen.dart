import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../models/asset.dart';
import '../../providers/assets_provider.dart';
import '../../widgets/common/empty_state.dart';

final _assetCategoryFilterProvider =
    StateProvider<AssetCategory?>((ref) => null);
final _showInactivosProvider = StateProvider<bool>((ref) => false);

class AssetsScreen extends ConsumerWidget {
  const AssetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(assetsProvider);
    final categoriaFilter = ref.watch(_assetCategoryFilterProvider);
    final showInactivos = ref.watch(_showInactivosProvider);

    final now = DateTime.now();
    final quarter = ((now.month - 1) ~/ 3) + 1;
    final amortizacionAsync = ref.watch(
      assetAmortizacionTrimestreProvider((year: now.year, quarter: quarter)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inversiones'),
        actions: [
          IconButton(
            icon: Icon(
              showInactivos
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: showInactivos ? AppColors.primary : null,
            ),
            tooltip: showInactivos ? 'Ocultar dados de baja' : 'Mostrar dados de baja',
            onPressed: () {
              ref.read(_showInactivosProvider.notifier).state = !showInactivos;
            },
          ),
          PopupMenuButton<AssetCategory?>(
            icon: Icon(
              Icons.filter_list,
              color: categoriaFilter != null ? AppColors.primary : null,
            ),
            tooltip: 'Filtrar por categoría',
            onSelected: (value) {
              ref.read(_assetCategoryFilterProvider.notifier).state = value;
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('Todas las categorías'),
              ),
              const PopupMenuDivider(),
              ...AssetCategory.values.map(
                (cat) => PopupMenuItem(
                  value: cat,
                  child: Row(
                    children: [
                      Icon(cat.icono, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(cat.label),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: assetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (assets) {
          final filtered = assets.where((a) {
            if (!showInactivos && !a.activo) return false;
            if (categoriaFilter != null && a.categoria != categoriaFilter) {
              return false;
            }
            return true;
          }).toList();

          if (filtered.isEmpty) {
            return const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Sin inversiones. Añade la primera con el botón +',
            );
          }

          return Column(
            children: [
              _ResumenBanner(
                assets: assets.where((a) => a.activo).toList(),
                amortizacionTrimestreAsync: amortizacionAsync,
                year: now.year,
                quarter: quarter,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _AssetCard(
                      asset: filtered[index],
                      onTap: () =>
                          context.push('/asset/${filtered[index].id}'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/asset/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ResumenBanner extends StatelessWidget {
  final List<Asset> assets;
  final AsyncValue<double> amortizacionTrimestreAsync;
  final int year;
  final int quarter;

  const _ResumenBanner({
    required this.assets,
    required this.amortizacionTrimestreAsync,
    required this.year,
    required this.quarter,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final totalInversion =
        assets.fold<double>(0.0, (s, a) => s + a.importeTotal);
    final valorContableTotal =
        assets.fold<double>(0.0, (s, a) => s + a.valorContable);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Inversión total',
                  value: fmt.format(totalInversion),
                ),
              ),
              Container(width: 1, height: 32, color: AppColors.divider),
              Expanded(
                child: _Stat(
                  label: 'Valor contable',
                  value: fmt.format(valorContableTotal),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.trending_down,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Amortización T$quarter $year: ',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              amortizacionTrimestreAsync.when(
                loading: () => const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) => const Text('-'),
                data: (v) => Text(
                  fmt.format(v),
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _AssetCard extends StatelessWidget {
  final Asset asset;
  final VoidCallback onTap;

  const _AssetCard({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final pct = asset.importeTotal > 0
        ? (asset.amortizacionAcumulada / asset.importeTotal).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: asset.activo
                          ? AppColors.primaryLight
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      asset.categoria.icono,
                      size: 20,
                      color: asset.activo
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          asset.descripcion,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: asset.activo
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            decoration: asset.activo
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          asset.categoria.label,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fmt.format(asset.valorContable),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Valor contable',
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: AppColors.cardBorder,
                        color: asset.estaAmortizado
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(pct * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    fmt.format(asset.cuotaAnual) + '/año',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary),
                  ),
                  if (asset.estaAmortizado)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Amortizado',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.success),
                      ),
                    )
                  else if (!asset.activo)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Dado de baja',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
