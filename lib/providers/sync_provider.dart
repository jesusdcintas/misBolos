import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import '../repositories/client_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/asset_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/settings_repository.dart';
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

  const SyncState({
    this.status = SyncStatus.idle,
    this.message,
    this.lastSync,
  });

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

  SyncNotifier(this._ref) : super(const SyncState());

  SupabaseService get _supabase => SupabaseService.instance;

  bool get isAuthenticated => _supabase.isAuthenticated;

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
        debugPrint('[Sync] Pending deletion still failing: $tableName/$recordId — $e');
      }
    }
  }

  /// Sincroniza datos locales a la nube
  Future<void> uploadToCloud() async {
    if (!_supabase.isAuthenticated) {
      state = state.copyWith(status: SyncStatus.error, message: 'No autenticado en la nube');
      return;
    }

    state = state.copyWith(status: SyncStatus.syncing, message: 'Subiendo datos...');

    try {
      // Primero procesar borrados pendientes para limpiar la nube
      await processPendingDeletions();

      final clients = await ClientRepository.instance.getAll();
      final gigs = await GigRepository.instance.getAll();
      final invoices = await InvoiceRepository.instance.getAll();
      final settings = await SettingsRepository().get();

      // Asignar cloud_id a expenses sin él
      final uuid = const Uuid();
      var expenses = await ExpenseRepository.instance.getAll();
      for (var i = 0; i < expenses.length; i++) {
        if (expenses[i].cloudId == null) {
          final cloudId = uuid.v4();
          await ExpenseRepository.instance.saveCloudId(expenses[i].id!, cloudId);
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

      await _supabase.uploadAll(
        clients: clients,
        gigs: gigs,
        invoices: invoices,
      );

      await _supabase.uploadExpenses(expenses);
      await _supabase.uploadAssets(assets);

      // Subir settings (datos de facturación)
      await _supabase.uploadSettings(settings);

      state = state.copyWith(
        status: SyncStatus.success,
        message: 'Datos subidos correctamente',
        lastSync: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[Sync] Upload error: $e');
      state = state.copyWith(status: SyncStatus.error, message: 'Error: $e');
    }
  }

  /// Descarga datos de la nube y los guarda localmente
  Future<void> downloadFromCloud() async {
    if (!_supabase.isAuthenticated) {
      state = state.copyWith(status: SyncStatus.error, message: 'No autenticado en la nube');
      return;
    }

    state = state.copyWith(status: SyncStatus.syncing, message: 'Descargando datos...');

    try {
      // Primero procesar borrados pendientes para que la nube esté limpia
      await processPendingDeletions();

      // Descargar de Supabase
      final cloudClients = await _supabase.downloadClients();
      final cloudGigs = await _supabase.downloadGigs();
      final cloudInvoices = await _supabase.downloadInvoices();
      final cloudSettings = await _supabase.downloadSettings();
      final cloudExpenses = await _supabase.downloadExpenses();
      final cloudAssets = await _supabase.downloadAssets();

      // Guardar en local (upsert)
      for (final client in cloudClients) {
        await ClientRepository.instance.upsert(client);
      }
      for (final gig in cloudGigs) {
        await GigRepository.instance.upsert(gig);
      }
      for (final invoice in cloudInvoices) {
        await InvoiceRepository.instance.upsert(invoice);
      }
      for (final expense in cloudExpenses) {
        await ExpenseRepository.instance.upsertByCloudId(expense);
      }
      for (final asset in cloudAssets) {
        await AssetRepository.instance.upsertByCloudId(asset);
      }

      // Eliminar registros locales que ya no existen en la nube
      // (fueron eliminados desde otro dispositivo o desde este mismo)
      final cloudClientIds = cloudClients.map((c) => c.id).toSet();
      final cloudGigIds = cloudGigs.map((g) => g.id).toSet();
      final cloudInvoiceIds = cloudInvoices.map((i) => i.id).toSet();

      final localClients = await ClientRepository.instance.getAll();
      for (final c in localClients) {
        if (!cloudClientIds.contains(c.id)) {
          await ClientRepository.instance.delete(c.id);
          debugPrint('[Sync] Removed local orphan client: ${c.id}');
        }
      }
      final localGigs = await GigRepository.instance.getAll();
      for (final g in localGigs) {
        if (!cloudGigIds.contains(g.id)) {
          await GigRepository.instance.delete(g.id);
          debugPrint('[Sync] Removed local orphan gig: ${g.id}');
        }
      }
      final localInvoices = await InvoiceRepository.instance.getAll();
      for (final i in localInvoices) {
        if (!cloudInvoiceIds.contains(i.id)) {
          await InvoiceRepository.instance.delete(i.id);
          debugPrint('[Sync] Removed local orphan invoice: ${i.id}');
        }
      }

      // Eliminar expenses y assets locales que ya no existen en la nube
      final cloudExpenseCloudIds = cloudExpenses
          .where((e) => e.cloudId != null)
          .map((e) => e.cloudId!)
          .toSet();
      final localExpenses = await ExpenseRepository.instance.getAll();
      for (final e in localExpenses) {
        if (e.cloudId != null && !cloudExpenseCloudIds.contains(e.cloudId)) {
          await ExpenseRepository.instance.deleteByCloudId(e.cloudId!);
          debugPrint('[Sync] Removed local orphan expense: ${e.cloudId}');
        }
      }

      final cloudAssetCloudIds = cloudAssets
          .where((a) => a.cloudId != null)
          .map((a) => a.cloudId!)
          .toSet();
      final localAssets = await AssetRepository.instance.getAll();
      for (final a in localAssets) {
        if (a.cloudId != null && !cloudAssetCloudIds.contains(a.cloudId)) {
          await AssetRepository.instance.deleteByCloudId(a.cloudId!);
          debugPrint('[Sync] Removed local orphan asset: ${a.cloudId}');
        }
      }

      // Guardar settings si existen en la nube
      if (cloudSettings != null) {
        debugPrint('[Sync] Saving settings with logoPath: ${cloudSettings.logoPath}');
        await SettingsRepository().save(cloudSettings);
      }

      // Invalidar providers para refrescar UI
      _ref.invalidate(clientsProvider);
      _ref.invalidate(gigsProvider);
      _ref.invalidate(invoicesProvider);
      _ref.invalidate(settingsProvider);
      _ref.invalidate(expensesProvider);
      _ref.invalidate(assetsProvider);

      state = state.copyWith(
        status: SyncStatus.success,
        message: 'Descargados: ${cloudClients.length} clientes, ${cloudGigs.length} bolos, '
            '${cloudInvoices.length} facturas, ${cloudExpenses.length} gastos, ${cloudAssets.length} inversiones',
        lastSync: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[Sync] Download error: $e');
      state = state.copyWith(status: SyncStatus.error, message: 'Error: $e');
    }
  }

  /// Sincronización bidireccional: sube local, descarga nuevo
  Future<void> syncAll() async {
    await uploadToCloud();
    if (state.status == SyncStatus.success) {
      await downloadFromCloud();
    }
  }

  void clearStatus() {
    state = state.copyWith(status: SyncStatus.idle, message: null);
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});

final isCloudAuthenticatedProvider = Provider<bool>((ref) {
  return SupabaseService.instance.isAuthenticated;
});
