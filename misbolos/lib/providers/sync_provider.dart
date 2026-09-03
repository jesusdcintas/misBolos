import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/app_settings.dart';
import '../services/supabase_service.dart';
import '../services/sync_queue_processor.dart';
import '../repositories/client_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/asset_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/sync_queue_repository.dart';
import 'client_provider.dart';
import 'expenses_provider.dart';
import 'assets_provider.dart';
import 'gig_provider.dart';
import 'invoice_provider.dart';
import 'settings_provider.dart';

/// Provider para el estado de autenticación de Supabase (reactivo)
final supabaseAuthProvider = StreamProvider<bool>((ref) {
  final stream = SupabaseService.instance.authStateChanges;
  if (stream == null) {
    return Stream.value(false);
  }
  return stream.map((authState) => authState.session != null);
});

enum SyncStatus { idle, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final String? message;
  final DateTime? lastSync;

  const SyncState({this.status = SyncStatus.idle, this.message, this.lastSync});

  SyncState copyWith({
    SyncStatus? status,
    String? message,
    DateTime? lastSync,
  }) {
    return SyncState(
      status: status ?? this.status,
      message: message ?? this.message,
      lastSync: lastSync ?? this.lastSync,
    );
  }
}

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  static Future<void>? _globalSyncInFlight;
  static String? _globalSyncReason;

  SyncNotifier(this._ref) : super(const SyncState());

  SupabaseService get _supabase => SupabaseService.instance;

  bool get isAuthenticated => _supabase.isAuthenticated;
  bool get isSyncInFlight => _globalSyncInFlight != null;

  bool _shouldRunDefensiveCloudPull(String reason) {
    switch (reason) {
      case 'manual_button':
      case 'pull_to_refresh':
      case 'periodic_auto':
      case 'app_resume':
      case 'app_start':
        return true;
      default:
        return false;
    }
  }

  bool _shouldForceFullCorePull(String reason) {
    switch (reason) {
      case 'manual_button':
      case 'pull_to_refresh':
      case 'auth_signed_in':
      case 'app_start':
        return true;
      default:
        return false;
    }
  }

  bool _shouldForceFullCorePush(String reason) {
    switch (reason) {
      case 'manual_button':
      case 'pull_to_refresh':
      case 'auth_signed_in':
      case 'app_start':
        return true;
      default:
        return false;
    }
  }

  String _friendlySyncError(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('failed host lookup') ||
        msg.contains('socketexception') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('timed out')) {
      return 'Sin conexión a internet. Reintenta cuando vuelvas a estar conectado.';
    }
    return 'No se pudieron sincronizar algunos datos.';
  }

  /// Procesa borrados pendientes que fallaron offline/por error
  Future<void> processPendingDeletions() async {
    if (!_supabase.isAuthenticated) return;

    final dbHelper = DatabaseHelper.instance;
    final pending = await dbHelper.getPendingDeletions();
    if (pending.isEmpty) return;

    debugPrint('[Sync] Processing ${pending.length} pending deletions...');
    for (final row in pending) {
      final tableName = row['table_name'] as String;
      final recordId = row['record_id'] as String;
      final pendingId = row['id'] as String;

      try {
        await _supabase.deleteByTable(tableName, recordId);
        await dbHelper.removePendingDeletion(pendingId);
        debugPrint('[Sync] Pending deletion processed: $tableName/$recordId');
      } catch (e) {
        debugPrint(
          '[Sync] Pending deletion still failing: $tableName/$recordId — $e',
        );
      }
    }
  }

  /// Sincroniza datos locales a la nube
  Future<void> uploadToCloud({
    String reason = 'manual_button',
    bool useGlobalLock = true,
  }) async {
    if (useGlobalLock) {
      return _runWithGlobalSyncLock(
        reason: reason,
        action: () async {
          debugPrint('[SYNC][DATA] start');
          await uploadToCloud(reason: reason, useGlobalLock: false);
        },
      );
    }
    if (!_supabase.isAuthenticated) {
      state = state.copyWith(
        status: SyncStatus.error,
        message: 'No autenticado en la nube',
      );
      return;
    }

    state = state.copyWith(
      status: SyncStatus.syncing,
      message: 'Subiendo datos...',
    );

    try {
      final syncStart = Stopwatch()..start();
      final settingsRepo = SettingsRepository();
      final settings = await settingsRepo.get();
      final lastSyncAt = settings.lastCloudSyncAt;

      final clientsWatch = Stopwatch()..start();
      final forceFullCorePush = _shouldForceFullCorePush(reason);
      final clients = await ClientRepository.instance.getAll();
      final changedClients = forceFullCorePush || lastSyncAt == null
          ? clients
          : clients.where((c) => c.updatedAt.isAfter(lastSyncAt)).toList();
      if (changedClients.isNotEmpty) {
        await _supabase.uploadClients(changedClients);
      }
      if (forceFullCorePush) {
        debugPrint('[SYNC][DATA] clients push completo (reason=$reason)');
      }
      clientsWatch.stop();
      debugPrint(
        '[SYNC][DATA] clients: count=${clients.length}, downloaded=0, '
        'uploaded=${changedClients.length}, skipped=${clients.length - changedClients.length}, '
        'time=${clientsWatch.elapsedMilliseconds} ms',
      );

      final gigsWatch = Stopwatch()..start();
      await processPendingDeletions();
      await SyncQueueProcessor.instance.processPending(
        reason: 'upload_to_cloud_$reason',
      );
      gigsWatch.stop();
      debugPrint(
        '[SYNC][DATA] gigs: count=queue, downloaded=0, uploaded=queue, skipped=0, '
        'time=${gigsWatch.elapsedMilliseconds} ms',
      );

      final invoicesWatch = Stopwatch()..start();
      final invoices = await InvoiceRepository.instance.getAll();
      final repaired = await GigRepository.instance.repairStatusesFromInvoices(
        invoices,
      );
      if (repaired > 0) {
        debugPrint(
          '[Sync] Repaired $repaired local gig statuses before upload',
        );
      }
      invoicesWatch.stop();
      debugPrint(
        '[SYNC][DATA] invoices: count=${invoices.length}, downloaded=0, uploaded=queue, '
        'skipped=${invoices.length}, time=${invoicesWatch.elapsedMilliseconds} ms',
      );

      // Asignar cloud_id a expenses sin él
      final expensesWatch = Stopwatch()..start();
      final uuid = const Uuid();
      var expenses = await ExpenseRepository.instance.getAll();
      for (var i = 0; i < expenses.length; i++) {
        if (expenses[i].cloudId == null) {
          final cloudId = uuid.v4();
          await ExpenseRepository.instance.saveCloudId(
            expenses[i].id!,
            cloudId,
          );
          expenses[i] = expenses[i].copyWith(cloudId: cloudId);
        }
      }

      // Asignar cloud_id a assets sin él
      var assets = await AssetRepository.instance.getAll();
      for (var i = 0; i < assets.length; i++) {
        if (assets[i].cloudId == null) {
          final cloudId = uuid.v4();
          await AssetRepository.instance.saveCloudId(assets[i].id!, cloudId);
          assets[i] = assets[i].copyWith(cloudId: cloudId);
        }
      }

      final unsyncedExpenses = expenses.where((e) => !e.synced).toList();
      if (unsyncedExpenses.isNotEmpty) {
        await _supabase.uploadExpenses(unsyncedExpenses);
        for (final expense in unsyncedExpenses) {
          if (expense.id != null) {
            await ExpenseRepository.instance.update(
              expense.copyWith(synced: true),
            );
          }
        }
      }
      expensesWatch.stop();
      debugPrint(
        '[SYNC][DATA] expenses: count=${expenses.length}, downloaded=0, '
        'uploaded=${unsyncedExpenses.length}, skipped=${expenses.length - unsyncedExpenses.length}, '
        'time=${expensesWatch.elapsedMilliseconds} ms',
      );

      final assetsWatch = Stopwatch()..start();
      final unsyncedAssets = assets.where((a) => !a.synced).toList();
      if (unsyncedAssets.isNotEmpty) {
        await _supabase.uploadAssets(unsyncedAssets);
        for (final asset in unsyncedAssets) {
          if (asset.id != null) {
            await AssetRepository.instance.update(asset.copyWith(synced: true));
          }
        }
      }
      assetsWatch.stop();
      debugPrint(
        '[SYNC][DATA] assets: count=${assets.length}, downloaded=0, '
        'uploaded=${unsyncedAssets.length}, skipped=${assets.length - unsyncedAssets.length}, '
        'time=${assetsWatch.elapsedMilliseconds} ms',
      );

      // Subir settings (datos de facturación)
      await _supabase.uploadSettings(settings);
      await settingsRepo.save(
        (await settingsRepo.get()).copyWith(
          cloudSettingsSignature: _supabase.settingsSyncSignature(settings),
        ),
      );

      debugPrint(
        '[Sync] Upload incremental done clients=${changedClients.length} '
        'expenses=${unsyncedExpenses.length} assets=${unsyncedAssets.length} '
        'elapsedMs=${syncStart.elapsedMilliseconds}',
      );
      debugPrint('[SYNC][DATA] total: ${syncStart.elapsedMilliseconds} ms');

      state = state.copyWith(
        status: SyncStatus.success,
        message: 'Datos subidos correctamente',
        lastSync: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[Sync] Upload error: $e');
      state = state.copyWith(
        status: SyncStatus.error,
        message: _friendlySyncError(e),
      );
    }
  }

  /// Descarga datos de la nube y los guarda localmente
  Future<void> downloadFromCloud({
    String reason = 'manual_button',
    bool useGlobalLock = true,
  }) async {
    if (useGlobalLock) {
      return _runWithGlobalSyncLock(
        reason: reason,
        action: () async {
          debugPrint('[SYNC][DATA] start');
          await downloadFromCloud(reason: reason, useGlobalLock: false);
        },
      );
    }
    if (!_supabase.isAuthenticated) {
      state = state.copyWith(
        status: SyncStatus.error,
        message: 'No autenticado en la nube',
      );
      return;
    }

    state = state.copyWith(
      status: SyncStatus.syncing,
      message: 'Descargando datos...',
    );

    try {
      final syncStart = Stopwatch()..start();
      await processPendingDeletions();
      await SyncQueueProcessor.instance.processPending(
        reason: 'download_from_cloud_$reason',
      );
      final settingsRepo = SettingsRepository();
      final settings = await settingsRepo.get();
      final lastSyncAt = settings.lastCloudSyncAt;
      final localClients = await ClientRepository.instance.getAll();
      final localGigs = await GigRepository.instance.getAll();
      final localInvoices = await InvoiceRepository.instance.getAll();

      // Descargar solo cambios desde Supabase
      final clientsWatch = Stopwatch()..start();
      final forceFullCorePull = _shouldForceFullCorePull(reason);
      var cloudClients = await _supabase.downloadClientsChangesSince(
        forceFullCorePull ? null : lastSyncAt,
      );
      if (forceFullCorePull) {
        debugPrint('[SYNC][DATA] clients pull completo (reason=$reason)');
      }
      if (cloudClients.isEmpty &&
          localClients.isEmpty &&
          lastSyncAt != null &&
          _shouldRunDefensiveCloudPull(reason)) {
        debugPrint(
          '[SYNC][DATA] clients incremental vacío con local vacío; ejecutando pull defensivo completo',
        );
        cloudClients = await _supabase.downloadClientsChangesSince(null);
      }
      clientsWatch.stop();
      final gigsWatch = Stopwatch()..start();
      var cloudGigs = await _supabase.downloadGigs(
        changedAfter: forceFullCorePull ? null : lastSyncAt,
      );
      if (forceFullCorePull) {
        debugPrint('[SYNC][DATA] gigs pull completo (reason=$reason)');
      }
      if (cloudGigs.isEmpty &&
          localGigs.isEmpty &&
          lastSyncAt != null &&
          _shouldRunDefensiveCloudPull(reason)) {
        debugPrint(
          '[SYNC][DATA] gigs incremental vacío con local vacío; ejecutando pull defensivo completo',
        );
        cloudGigs = await _supabase.downloadGigs(changedAfter: null);
      }
      gigsWatch.stop();
      final invoicesWatch = Stopwatch()..start();
      final forceFullInvoicesPull =
          forceFullCorePull && _shouldRunDefensiveCloudPull(reason);
      var cloudInvoices = await _supabase.downloadInvoices(
        changedAfter: forceFullInvoicesPull ? null : lastSyncAt,
      );
      if (forceFullInvoicesPull) {
        debugPrint(
          '[SYNC][DATA] invoices pull completo forzado (reason=$reason)',
        );
      }
      if (cloudInvoices.isEmpty &&
          localInvoices.isEmpty &&
          lastSyncAt != null &&
          _shouldRunDefensiveCloudPull(reason)) {
        debugPrint(
          '[SYNC][DATA] invoices incremental vacío con local vacío; ejecutando pull defensivo completo',
        );
        cloudInvoices = await _supabase.downloadInvoices(changedAfter: null);
      }
      invoicesWatch.stop();
      final cloudSettings = await _supabase.downloadSettings(
        changedAfter: lastSyncAt,
      );
      final expensesWatch = Stopwatch()..start();
      final forceFullExpensesPull =
          reason == 'app_start' && _shouldRunDefensiveCloudPull(reason);
      var cloudExpenses = await _supabase.downloadExpenseChangesRaw(
        changedAfter: forceFullExpensesPull ? null : lastSyncAt,
      );
      if (forceFullExpensesPull) {
        debugPrint(
          '[SYNC][DATA] expenses pull completo forzado (reason=$reason)',
        );
      }
      if (cloudExpenses.isEmpty &&
          lastSyncAt != null &&
          _shouldRunDefensiveCloudPull(reason)) {
        debugPrint(
          '[SYNC][DATA] expenses incremental vacío; ejecutando pull defensivo completo',
        );
        cloudExpenses = await _supabase.downloadExpenseChangesRaw(
          changedAfter: null,
        );
      }
      expensesWatch.stop();
      final assetsWatch = Stopwatch()..start();
      final forceFullAssetsPull =
          reason == 'app_start' && _shouldRunDefensiveCloudPull(reason);
      var cloudAssets = await _supabase.downloadAssetChangesRaw(
        changedAfter: forceFullAssetsPull ? null : lastSyncAt,
      );
      if (forceFullAssetsPull) {
        debugPrint(
          '[SYNC][DATA] assets pull completo forzado (reason=$reason)',
        );
      }
      if (cloudAssets.isEmpty &&
          lastSyncAt != null &&
          _shouldRunDefensiveCloudPull(reason)) {
        debugPrint(
          '[SYNC][DATA] assets incremental vacío; ejecutando pull defensivo completo',
        );
        cloudAssets = await _supabase.downloadAssetChangesRaw(
          changedAfter: null,
        );
      }
      assetsWatch.stop();

      var clientsChanged = 0;
      var gigsChanged = 0;
      var invoicesChanged = 0;
      var expensesChanged = 0;
      var assetsChanged = 0;
      var skippedUnchanged = 0;

      // Guardar en local (upsert)
      for (final client in cloudClients) {
        final local = await ClientRepository.instance.getById(client.id);
        if (local == null || client.updatedAt.isAfter(local.updatedAt)) {
          await ClientRepository.instance.upsert(client);
          clientsChanged++;
        } else {
          skippedUnchanged++;
        }
      }
      debugPrint(
        '[SYNC][DATA] clients: count=${cloudClients.length}, downloaded=${cloudClients.length}, '
        'uploaded=0, skipped=${cloudClients.length - clientsChanged}, time=${clientsWatch.elapsedMilliseconds} ms',
      );
      for (final gig in cloudGigs) {
        if (gig.deletedAt != null) {
          await GigRepository.instance.delete(gig.id);
          gigsChanged++;
          continue;
        }
        final hasPending = await SyncQueueRepository.instance.hasPending(
          'gig',
          gig.id,
        );
        if (hasPending) continue;
        final local = await GigRepository.instance.getById(gig.id);
        if (local == null || gig.updatedAt.isAfter(local.updatedAt)) {
          await GigRepository.instance.upsert(gig);
          gigsChanged++;
        } else {
          skippedUnchanged++;
        }
      }
      debugPrint(
        '[SYNC][DATA] gigs: count=${cloudGigs.length}, downloaded=${cloudGigs.length}, '
        'uploaded=0, skipped=${cloudGigs.length - gigsChanged}, time=${gigsWatch.elapsedMilliseconds} ms',
      );
      for (final invoice in cloudInvoices) {
        if (invoice.deletedAt != null) {
          await InvoiceRepository.instance.delete(invoice.id);
          invoicesChanged++;
          continue;
        }
        final hasPending = await SyncQueueRepository.instance.hasPending(
          'invoice',
          invoice.id,
        );
        if (hasPending) continue;
        final local = await InvoiceRepository.instance.getById(invoice.id);
        final numberDiffers = local != null && local.numero != invoice.numero;
        if (local == null ||
            invoice.updatedAt.isAfter(local.updatedAt) ||
            numberDiffers) {
          String? source;
          if (numberDiffers) {
            // En descarga cloud->local la numeración remota debe prevalecer:
            // evita divergencias entre dispositivos cuando un local quedó desfasado.
            source = InvoiceNumberChangeSource.manualRenumber;
            debugPrint(
              '[InvoiceNumber] download aplicando número remoto '
              'invoice_id=${invoice.id} local=${local.numero} remote=${invoice.numero}',
            );
          }
          await InvoiceRepository.instance.upsert(
            invoice,
            allowedNumberChangeSource: source,
          );
          invoicesChanged++;
        } else {
          skippedUnchanged++;
        }
      }
      debugPrint(
        '[SYNC][DATA] invoices: count=${cloudInvoices.length}, downloaded=${cloudInvoices.length}, '
        'uploaded=0, skipped=${cloudInvoices.length - invoicesChanged}, time=${invoicesWatch.elapsedMilliseconds} ms',
      );
      final repaired = await GigRepository.instance.repairStatusesFromInvoices(
        cloudInvoices,
      );
      if (repaired > 0) {
        debugPrint(
          '[Sync] Repaired $repaired local gig statuses after download',
        );
      }
      for (final row in cloudExpenses) {
        final cloudId = row['id']?.toString();
        if (cloudId == null || cloudId.isEmpty) continue;
        if (row['deleted_at'] != null) {
          await ExpenseRepository.instance.deleteByCloudId(cloudId);
          expensesChanged++;
          continue;
        }
        final expense = _supabase.expenseFromCloudRow(row);
        await ExpenseRepository.instance.upsertByCloudId(expense);
        expensesChanged++;
      }
      debugPrint(
        '[SYNC][DATA] expenses: count=${cloudExpenses.length}, downloaded=${cloudExpenses.length}, '
        'uploaded=0, skipped=${cloudExpenses.length - expensesChanged}, time=${expensesWatch.elapsedMilliseconds} ms',
      );
      for (final row in cloudAssets) {
        final cloudId = row['id']?.toString();
        if (cloudId == null || cloudId.isEmpty) continue;
        if (row['deleted_at'] != null) {
          await AssetRepository.instance.deleteByCloudId(cloudId);
          assetsChanged++;
          continue;
        }
        final asset = _supabase.assetFromCloudRow(row);
        await AssetRepository.instance.upsertByCloudId(asset);
        assetsChanged++;
      }
      debugPrint(
        '[SYNC][DATA] assets: count=${cloudAssets.length}, downloaded=${cloudAssets.length}, '
        'uploaded=0, skipped=${cloudAssets.length - assetsChanged}, time=${assetsWatch.elapsedMilliseconds} ms',
      );

      // Guardar settings si existen en la nube
      if (cloudSettings != null) {
        final localSettings = await SettingsRepository().get();
        final mergedSettings = _mergeDownloadedSettings(
          localSettings,
          cloudSettings,
        );
        debugPrint(
          '[Sync] Saving settings with logoPath: ${mergedSettings.logoPath}',
        );
        await SettingsRepository().save(
          mergedSettings.copyWith(
            cloudSettingsSignature: _supabase.settingsSyncSignature(
              mergedSettings,
            ),
          ),
        );
      }

      final syncEndedAt = DateTime.now();
      final saveWatch = Stopwatch()..start();
      await settingsRepo.save(
        (await settingsRepo.get()).copyWith(lastCloudSyncAt: syncEndedAt),
      );
      saveWatch.stop();
      debugPrint('[SYNC] save lastSyncAt: ${saveWatch.elapsedMilliseconds} ms');

      // Invalidar providers para refrescar UI
      if (clientsChanged > 0) _ref.invalidate(clientsProvider);
      if (gigsChanged > 0) _ref.invalidate(gigsProvider);
      if (invoicesChanged > 0) _ref.invalidate(invoicesProvider);
      _ref.invalidate(settingsProvider);
      if (expensesChanged > 0) _ref.invalidate(expensesProvider);
      if (assetsChanged > 0) _ref.invalidate(assetsProvider);

      debugPrint(
        '[Sync] Download incremental done '
        'clients=$clientsChanged gigs=$gigsChanged invoices=$invoicesChanged '
        'expenses=$expensesChanged assets=$assetsChanged skipped=$skippedUnchanged '
        'elapsedMs=${syncStart.elapsedMilliseconds}',
      );
      debugPrint('[SYNC][DATA] total: ${syncStart.elapsedMilliseconds} ms');

      state = state.copyWith(
        status: SyncStatus.success,
        message: 'Sincronizado',
        lastSync: syncEndedAt,
      );
    } catch (e) {
      debugPrint('[Sync] Download error: $e');
      state = state.copyWith(
        status: SyncStatus.error,
        message: _friendlySyncError(e),
      );
    }
  }

  /// Sincronización bidireccional: sube local, descarga nuevo
  Future<void> syncAll({String reason = 'manual_button'}) async {
    return _runWithGlobalSyncLock(
      reason: reason,
      action: () async {
        debugPrint('[SYNC][DATA] start');
        await _syncAllInternal(reason: reason);
      },
    );
  }

  Future<void> _runWithGlobalSyncLock({
    required String reason,
    required Future<void> Function() action,
  }) async {
    final totalWatch = Stopwatch()..start();
    debugPrint('[SYNC] start reason=$reason');
    final running = _globalSyncInFlight;
    if (running != null) {
      debugPrint(
        '[SYNC] skipped reason=$reason; already running reason=$_globalSyncReason',
      );
      return running;
    }
    debugPrint('[SYNC] acquire lock: ${totalWatch.elapsedMilliseconds} ms');
    _globalSyncReason = reason;
    _globalSyncInFlight = action().timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        throw TimeoutException('La sincronización ha tardado demasiado.');
      },
    );
    try {
      await _globalSyncInFlight;
    } on TimeoutException catch (e) {
      debugPrint('[SYNC] timeout reason=$reason: $e');
      state = state.copyWith(
        status: SyncStatus.error,
        message:
            'La sincronización ha tardado demasiado. Reintenta en un momento.',
      );
    } finally {
      debugPrint(
        '[SYNC] total: ${totalWatch.elapsedMilliseconds} ms status=${state.status.name}',
      );
      _globalSyncInFlight = null;
      _globalSyncReason = null;
    }
  }

  Future<void> _syncAllInternal({required String reason}) async {
    final dataWatch = Stopwatch()..start();
    await uploadToCloud(reason: reason, useGlobalLock: false);
    if (state.status == SyncStatus.success) {
      await downloadFromCloud(reason: reason, useGlobalLock: false);
    }
    dataWatch.stop();
    debugPrint('[SYNC][DATA] total: ${dataWatch.elapsedMilliseconds} ms');
  }

  void clearStatus() {
    state = state.copyWith(status: SyncStatus.idle, message: null);
  }

  AppSettings _mergeDownloadedSettings(AppSettings local, AppSettings cloud) {
    String keepLocalIfCloudEmpty(String localValue, String cloudValue) {
      if (cloudValue.trim().isEmpty && localValue.trim().isNotEmpty) {
        return localValue;
      }
      return cloudValue;
    }

    return cloud.copyWith(
      logoPath: keepLocalIfCloudEmpty(local.logoPath, cloud.logoPath),
      logoSize: local.logoSize,
      pdfTheme: local.pdfTheme,
      emisorNombre: keepLocalIfCloudEmpty(
        local.emisorNombre,
        cloud.emisorNombre,
      ),
      emisorNIF: keepLocalIfCloudEmpty(local.emisorNIF, cloud.emisorNIF),
      emisorDireccion: keepLocalIfCloudEmpty(
        local.emisorDireccion,
        cloud.emisorDireccion,
      ),
      emisorCiudad: keepLocalIfCloudEmpty(
        local.emisorCiudad,
        cloud.emisorCiudad,
      ),
      emisorProvincia: keepLocalIfCloudEmpty(
        local.emisorProvincia,
        cloud.emisorProvincia,
      ),
      emisorCodigoPostal: keepLocalIfCloudEmpty(
        local.emisorCodigoPostal,
        cloud.emisorCodigoPostal,
      ),
      emisorEmail: keepLocalIfCloudEmpty(local.emisorEmail, cloud.emisorEmail),
      emisorTelefono: keepLocalIfCloudEmpty(
        local.emisorTelefono,
        cloud.emisorTelefono,
      ),
      iban: keepLocalIfCloudEmpty(local.iban, cloud.iban),
      notificacionesActivas: local.notificacionesActivas,
      diasRecordatorio: local.diasRecordatorio,
      driveConnected: local.driveConnected,
      driveAccountEmail: local.driveAccountEmail,
      driveAccountName: local.driveAccountName,
      driveRootFolderId: local.driveRootFolderId,
      driveRootFolderName: local.driveRootFolderName,
      lastDriveBackupAt: local.lastDriveBackupAt,
      lastDriveSyncAt: local.lastDriveSyncAt,
      lastCloudSyncAt: local.lastCloudSyncAt,
      cloudSettingsSignature: local.cloudSettingsSignature,
      securityPinEnabled: local.securityPinEnabled,
      securityPinCode: local.securityPinCode,
      securityBiometricEnabled: local.securityBiometricEnabled,
      securityLockDelaySeconds: local.securityLockDelaySeconds,
    );
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});

final isCloudAuthenticatedProvider = Provider<bool>((ref) {
  return SupabaseService.instance.isAuthenticated;
});

final syncQueuePendingCountProvider = StreamProvider<int>((ref) async* {
  while (true) {
    final total = await SyncQueueRepository.instance.countPending();
    yield total;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
});
