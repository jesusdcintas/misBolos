import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../models/asset.dart';
import '../../providers/assets_provider.dart';
import '../../widgets/common/empty_state.dart';

final _assetCategoryFilterProvider = StateProvider<AssetCategory?>(
  (ref) => null,
);
final _showInactivosProvider = StateProvider<bool>((ref) => false);

enum AssetSortOption { fechaDesc, fechaAsc, importeDesc, importeAsc, nombreAsc }

final _assetSortProvider = StateProvider<AssetSortOption>(
  (ref) => AssetSortOption.fechaDesc,
);

class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    Future.microtask(() => ref.read(assetsProvider.notifier).enterScreen());
  }

  @override
  void dispose() {
    ref.read(assetsProvider.notifier).leaveScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(assetsProvider);
    final categoriaFilter = ref.watch(_assetCategoryFilterProvider);
    final showInactivos = ref.watch(_showInactivosProvider);
    final sortOption = ref.watch(_assetSortProvider);

    final now = DateTime.now();
    final quarter = ((now.month - 1) ~/ 3) + 1;
    final amortizacionAsync = ref.watch(
      assetAmortizacionTrimestreProvider((year: now.year, quarter: quarter)),
    );

    return Scaffold(
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
          _sortAssets(filtered, sortOption);

          return Column(
            children: [
              const _CompactHeader(title: 'Inversiones'),
              _ResumenBanner(
                assets: assets.where((a) => a.activo).toList(),
                amortizacionTrimestreAsync: amortizacionAsync,
                year: now.year,
                quarter: quarter,
              ),
              _AssetActions(
                category: categoriaFilter,
                showInactive: showInactivos,
                sortOption: sortOption,
                onCategoryChanged: (value) {
                  ref.read(_assetCategoryFilterProvider.notifier).state = value;
                },
                onShowInactiveChanged: () {
                  ref.read(_showInactivosProvider.notifier).state =
                      !showInactivos;
                },
                onSortChanged: (value) {
                  ref.read(_assetSortProvider.notifier).state = value;
                },
              ),
              if (filtered.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'Sin inversiones para este filtro',
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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

  void _sortAssets(List<Asset> assets, AssetSortOption option) {
    assets.sort((a, b) {
      switch (option) {
        case AssetSortOption.fechaDesc:
          return b.fechaCompra.compareTo(a.fechaCompra);
        case AssetSortOption.fechaAsc:
          return a.fechaCompra.compareTo(b.fechaCompra);
        case AssetSortOption.importeDesc:
          return b.importeTotal.compareTo(a.importeTotal);
        case AssetSortOption.importeAsc:
          return a.importeTotal.compareTo(b.importeTotal);
        case AssetSortOption.nombreAsc:
          return a.descripcion.toLowerCase().compareTo(
            b.descripcion.toLowerCase(),
          );
      }
    });
  }
}

class _CompactHeader extends StatelessWidget {
  final String title;

  const _CompactHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _AssetActions extends StatelessWidget {
  final AssetCategory? category;
  final bool showInactive;
  final AssetSortOption sortOption;
  final ValueChanged<AssetCategory?> onCategoryChanged;
  final VoidCallback onShowInactiveChanged;
  final ValueChanged<AssetSortOption> onSortChanged;

  const _AssetActions({
    required this.category,
    required this.showInactive,
    required this.sortOption,
    required this.onCategoryChanged,
    required this.onShowInactiveChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: PopupMenuButton<AssetCategory?>(
              onSelected: onCategoryChanged,
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
                        Icon(
                          cat.icono,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(cat.label),
                      ],
                    ),
                  ),
                ),
              ],
              child: _ActionPill(
                icon: Icons.filter_list,
                label: category?.label ?? 'Categoría',
                active: category != null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<AssetSortOption>(
              onSelected: onSortChanged,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: AssetSortOption.fechaDesc,
                  child: Text('Fecha reciente'),
                ),
                PopupMenuItem(
                  value: AssetSortOption.fechaAsc,
                  child: Text('Fecha antigua'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: AssetSortOption.importeDesc,
                  child: Text('Importe mayor'),
                ),
                PopupMenuItem(
                  value: AssetSortOption.importeAsc,
                  child: Text('Importe menor'),
                ),
                PopupMenuItem(
                  value: AssetSortOption.nombreAsc,
                  child: Text('Nombre A-Z'),
                ),
              ],
              child: const _ActionPill(icon: Icons.sort, label: 'Ordenar'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onShowInactiveChanged,
                borderRadius: BorderRadius.circular(10),
                child: _ActionPill(
                  icon: showInactive
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  label: showInactive ? 'Bajas' : 'Activas',
                  active: showInactive,
                ),
              ),
            ),
          ),
        ],
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
    final totalInversion = assets.fold<double>(
      0.0,
      (s, a) => s + a.importeTotal,
    );
    final valorContableTotal = assets.fold<double>(
      0.0,
      (s, a) => s + a.valorContable,
    );

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
              const Icon(
                Icons.trending_down,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Amortización T$quarter $year: ',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              amortizacionTrimestreAsync.when(
                loading: () => const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const Text('-'),
                data: (v) => Text(
                  fmt.format(v),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
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

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _ActionPill({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textPrimary;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.cardBorder,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
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
                            color: AppColors.textSecondary,
                          ),
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
                          color: AppColors.textSecondary,
                        ),
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
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${fmt.format(asset.cuotaAnual)}/año',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (asset.estaAmortizado)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Amortizado',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.success,
                        ),
                      ),
                    )
                  else if (!asset.activo)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Dado de baja',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
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
