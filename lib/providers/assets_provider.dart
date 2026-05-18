import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/asset.dart';
import '../repositories/asset_repository.dart';
import '../core/services/drive_document_sync_service.dart';
import '../core/services/google_drive_service.dart';
import '../services/supabase_service.dart';
import '../services/ai_attachment_service.dart';
import '../repositories/settings_repository.dart';

final assetRepositoryProvider = Provider((ref) => AssetRepository.instance);

final assetsProvider = AsyncNotifierProvider<AssetsNotifier, List<Asset>>(
  AssetsNotifier.new,
);

class AssetsNotifier extends AsyncNotifier<List<Asset>> {
  RealtimeChannel? _assetsChannel;
  StreamSubscription<AuthState>? _authSubscription;
  bool _realtimeStarted = false;
  bool _initialPullDone = false;
  bool _isPulling = false;
  bool _isApplyingRemoteChange = false;

  @override
  Future<List<Asset>> build() async {
    _startRealtimeIfNeeded();
    return ref.read(assetRepositoryProvider).getAll();
  }

  Future<void> enterScreen() async {
    await pullInitialFromCloud();
    _startRealtimeIfNeeded();
  }

  void leaveScreen() {
    // Mantener realtime activo aunque salgas de la pantalla para reflejar
    // borrados/altas desde otros dispositivos sin sync manual.
  }

  Future<void> pullInitialFromCloud({bool force = false}) async {
    final supabase = SupabaseService.instance;
    if (!supabase.isAuthenticated) return;
    if (!force && _initialPullDone) return;
    if (_isPulling) return;

    _isPulling = true;
    try {
      debugPrint('[AssetsSync] Pull inicial assets (Supabase -> SQLite)');
      final remote = await supabase.downloadAssets();
      _isApplyingRemoteChange = true;
      try {
        for (final asset in remote) {
          await ref.read(assetRepositoryProvider).upsertByCloudId(asset);
        }
      } finally {
        _isApplyingRemoteChange = false;
      }
      _initialPullDone = true;
      await reloadLocal();
    } catch (e) {
      debugPrint('[AssetsSync] Pull inicial error: $e');
    } finally {
      _isPulling = false;
    }
  }

  void _startRealtimeIfNeeded() {
    if (_realtimeStarted) return;
    _realtimeStarted = true;

    final supabase = SupabaseService.instance;
    if (!supabase.isAuthenticated || supabase.userId == null) {
      debugPrint('[AssetsSync] Realtime no iniciado: sin sesión');
      return;
    }

    _authSubscription?.cancel();
    _authSubscription = supabase.authStateChanges?.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        _disposeRealtime();
      }
    });

    final client = Supabase.instance.client;
    _assetsChannel = client
        .channel('public:assets:user:${supabase.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'assets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: supabase.userId!,
          ),
          callback: _handleRealtimeEvent,
        )
        .subscribe();

    debugPrint('[AssetsSync] Realtime suscrito (assets)');
  }

  void _disposeRealtime() {
    final channel = _assetsChannel;
    _assetsChannel = null;
    _realtimeStarted = false;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
      debugPrint('[AssetsSync] Realtime desuscrito (assets)');
    }
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  Asset? _assetFromRealtimeRecord(Map<String, dynamic> m) {
    final cloudId = m['id']?.toString();
    final userId = m['user_id']?.toString();
    final descripcion = m['descripcion']?.toString();
    final fechaCompraRaw = m['fecha_compra']?.toString();
    final importeTotalRaw = m['importe_total'];
    final createdAtRaw = m['created_at']?.toString();
    if (cloudId == null ||
        userId == null ||
        descripcion == null ||
        fechaCompraRaw == null ||
        importeTotalRaw == null ||
        createdAtRaw == null) {
      return null;
    }

    try {
      return Asset(
        cloudId: cloudId,
        userId: userId,
        descripcion: descripcion,
        fechaCompra: DateTime.parse(fechaCompraRaw),
        importeTotal: (importeTotalRaw as num).toDouble(),
        importeConIva: (m['importe_con_iva'] as num? ?? 0).toDouble(),
        ivaRate: (m['iva_rate'] as num? ?? 21).toDouble(),
        ivaAmount: (m['iva_amount'] as num? ?? 0).toDouble(),
        valorResidual: (m['valor_residual'] as num? ?? 0).toDouble(),
        vidaUtilAnos: (m['vida_util_anos'] as num?)?.toInt() ?? 1,
        metodoAmortizacion: (m['metodo_amortizacion'] ?? 'lineal').toString(),
        categoria: AssetCategory.fromDb((m['categoria'] ?? 'otros').toString()),
        driveFileId: m['drive_file_id']?.toString(),
        driveFileUrl: m['drive_file_url']?.toString(),
        driveSyncedAt: m['drive_synced_at'] != null
            ? DateTime.tryParse(m['drive_synced_at'].toString())
            : null,
        documentoPath: m['documento_path']?.toString(),
        notas: m['notas']?.toString(),
        activo: m['activo'] as bool? ?? true,
        synced: true,
        createdAt: DateTime.parse(createdAtRaw),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleRealtimeEvent(PostgresChangePayload payload) async {
    if (_isPulling || _isApplyingRemoteChange) return;

    final event = payload.eventType;
    final id =
        (payload.newRecord['id'] ?? payload.oldRecord['id'])?.toString() ??
        'unknown';

    try {
      _isApplyingRemoteChange = true;
      if (event == PostgresChangeEvent.delete ||
          (event == PostgresChangeEvent.update &&
              payload.newRecord['deleted_at'] != null)) {
        final cloudId = payload.oldRecord['id']?.toString();
        final resolvedCloudId = cloudId ?? payload.newRecord['id']?.toString();
        if (resolvedCloudId != null) {
          await ref
              .read(assetRepositoryProvider)
              .deleteByCloudId(resolvedCloudId);
        }
      } else {
        final asset = _assetFromRealtimeRecord(payload.newRecord);
        if (asset == null) return;
        await ref.read(assetRepositoryProvider).upsertByCloudId(asset);
      }
      await reloadLocal();
      debugPrint(
        '[AssetsSync] Realtime ${event.name.toUpperCase()} asset_id=$id',
      );
    } catch (e) {
      debugPrint('[AssetsSync] Realtime error asset_id=$id: $e');
    } finally {
      _isApplyingRemoteChange = false;
    }
  }

  Future<void> reloadLocal() async {
    final assets = await ref.read(assetRepositoryProvider).getAll();
    state = AsyncData(assets);
  }

  Future<void> add(Asset asset) async {
    final repo = ref.read(assetRepositoryProvider);
    final localId = await repo.insert(
      asset.copyWith(synced: false, attachmentStatus: 'pending_upload'),
    );
    final saved = await repo.getById(localId);
    if (saved != null && saved.documentoPath != null) {
      try {
        final stablePath = await AiAttachmentService.instance
            .persistAttachmentForEntity(
              sourcePath: saved.documentoPath!,
              entityType: 'asset',
              entityId: saved.id.toString(),
            );
        await repo.update(
          saved.copyWith(
            documentoPath: stablePath,
            attachmentStatus: 'pending_upload',
            attachmentError: null,
            attachmentOriginalPath: saved.documentoPath,
            attachmentOriginalName: AiAttachmentService.instance
                .normalizeOriginalFileName(saved.documentoPath!),
            attachmentStoredName: p.basename(stablePath),
            attachmentMimeType: _mimeTypeFor(stablePath),
            synced: false,
          ),
        );
      } catch (e) {
        await repo.update(
          saved.copyWith(
            attachmentStatus: 'broken',
            attachmentError: e.toString(),
            attachmentOriginalPath: saved.documentoPath,
            synced: false,
          ),
        );
      }
    }
    ref.invalidateSelf();
    await _tryUploadAsset(localId);
    await _tryAutoSyncAssetToDrive(localId);
  }

  Future<void> updateAsset(Asset asset) async {
    final repo = ref.read(assetRepositoryProvider);
    var updated = asset.copyWith(synced: false);
    if (updated.documentoPath != null && updated.id != null) {
      try {
        final stablePath = await AiAttachmentService.instance
            .persistAttachmentForEntity(
              sourcePath: updated.documentoPath!,
              entityType: 'asset',
              entityId: updated.id.toString(),
            );
        updated = updated.copyWith(
          documentoPath: stablePath,
          attachmentStatus: 'pending_upload',
          attachmentError: null,
          attachmentOriginalPath: asset.documentoPath,
          attachmentOriginalName:
              asset.attachmentOriginalName ??
              AiAttachmentService.instance.normalizeOriginalFileName(
                asset.documentoPath!,
              ),
          attachmentStoredName: p.basename(stablePath),
          attachmentMimeType: _mimeTypeFor(stablePath),
        );
      } catch (e) {
        updated = updated.copyWith(
          attachmentStatus: 'broken',
          attachmentError: e.toString(),
          attachmentOriginalPath: asset.documentoPath,
        );
      }
    }
    await repo.update(updated);
    ref.invalidateSelf();
    if (asset.id != null) {
      await _tryUploadAsset(asset.id!);
      await _tryAutoSyncAssetToDrive(asset.id!);
    }
  }

  String _mimeTypeFor(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> remove(int id, {bool deleteFromDrive = false}) async {
    final repo = ref.read(assetRepositoryProvider);
    final existing = await repo.getById(id);
    if (deleteFromDrive && existing?.driveFileId?.trim().isNotEmpty == true) {
      try {
        await GoogleDriveService.instance.trashFile(existing!.driveFileId!);
      } catch (e) {
        debugPrint('[AssetsSync] No se pudo enviar a papelera en Drive: $e');
      }
    }
    if (existing?.cloudId != null) {
      await DatabaseHelper.instance.addPendingDeletion(
        'assets',
        existing!.cloudId!,
      );
      try {
        await SupabaseService.instance.deleteAsset(existing.cloudId!);
      } catch (e) {
        debugPrint('[AssetsSync] deleteAsset directo falló: $e');
      }
    }
    await repo.delete(id);
    await DriveDocumentSyncService.instance.removeQueueForEntity(
      entityType: 'asset',
      entityId: id.toString(),
    );
    ref.invalidateSelf();
  }

  Future<void> darDeBaja(int id) async {
    final asset = await ref.read(assetRepositoryProvider).getById(id);
    if (asset == null) return;
    await ref
        .read(assetRepositoryProvider)
        .update(asset.copyWith(activo: false));
    ref.invalidateSelf();
  }

  Future<void> _tryUploadAsset(int localId) async {
    final supabase = SupabaseService.instance;
    if (!supabase.isAuthenticated) return;
    final repo = ref.read(assetRepositoryProvider);
    final asset = await repo.getById(localId);
    if (asset == null) return;

    var updated = asset;
    if (updated.cloudId == null) {
      final cloudId = const Uuid().v4();
      await repo.saveCloudId(localId, cloudId);
      updated = updated.copyWith(cloudId: cloudId);
    }

    try {
      await supabase.uploadAssets([updated.copyWith(synced: true)]);
      await repo.update(
        updated.copyWith(
          synced: true,
          attachmentStatus: updated.documentoPath == null
              ? updated.attachmentStatus
              : 'pending_upload',
        ),
      );
      await reloadLocal();
    } catch (e) {
      debugPrint('[AssetsSync] Upload directo error: $e');
    }
  }

  Future<void> _tryAutoSyncAssetToDrive(int localId) async {
    final settings = await SettingsRepository().get();
    final ready =
        settings.driveConnected &&
        (settings.driveRootFolderId?.trim().isNotEmpty ?? false);
    if (!ready) return;
    try {
      await DriveDocumentSyncService.instance.syncAssetById(localId);
    } catch (e) {
      debugPrint('[AssetsSync] Auto Drive sync error asset_id=$localId: $e');
    }
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

final assetsProximosAmortizarProvider = FutureProvider.family<List<Asset>, int>(
  (ref, meses) {
    return ref.read(assetRepositoryProvider).getProximosAmortizar(meses);
  },
);
