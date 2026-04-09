import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import '../repositories/client_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/settings_repository.dart';
import 'client_provider.dart';
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

      await _supabase.uploadAll(
        clients: clients,
        gigs: gigs,
        invoices: invoices,
      );
      
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

      state = state.copyWith(
        status: SyncStatus.success,
        message: 'Datos descargados: ${cloudClients.length} clientes, ${cloudGigs.length} bolos, ${cloudInvoices.length} facturas',
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
