import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset.dart';
import '../repositories/asset_repository.dart';

final assetRepositoryProvider = Provider((ref) => AssetRepository.instance);

final assetsProvider = AsyncNotifierProvider<AssetsNotifier, List<Asset>>(
  AssetsNotifier.new,
);

class AssetsNotifier extends AsyncNotifier<List<Asset>> {
  @override
  Future<List<Asset>> build() async {
    return ref.read(assetRepositoryProvider).getAll();
  }

  Future<void> add(Asset asset) async {
    await ref.read(assetRepositoryProvider).insert(asset);
    ref.invalidateSelf();
  }

  Future<void> updateAsset(Asset asset) async {
    await ref.read(assetRepositoryProvider).update(asset);
    ref.invalidateSelf();
  }

  Future<void> remove(int id) async {
    await ref.read(assetRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }

  Future<void> darDeBaja(int id) async {
    final asset = await ref.read(assetRepositoryProvider).getById(id);
    if (asset == null) return;
    await ref.read(assetRepositoryProvider).update(asset.copyWith(activo: false));
    ref.invalidateSelf();
  }
}

final assetByIdProvider = FutureProvider.family<Asset?, int>((ref, id) {
  return ref.read(assetRepositoryProvider).getById(id);
});

final assetsActivosProvider = FutureProvider<List<Asset>>((ref) {
  return ref.read(assetRepositoryProvider).getActivos();
});

final assetAmortizacionTrimestreProvider =
    FutureProvider.family<double, ({int year, int quarter})>((ref, params) {
  return ref
      .read(assetRepositoryProvider)
      .getTotalAmortizacionTrimestre(params.year, params.quarter);
});

final assetsProximosAmortizarProvider =
    FutureProvider.family<List<Asset>, int>((ref, meses) {
  return ref.read(assetRepositoryProvider).getProximosAmortizar(meses);
});
