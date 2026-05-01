import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_event.dart';
import '../models/gig.dart';
import '../repositories/app_event_repository.dart';
import '../repositories/gig_repository.dart';
import 'invoice_provider.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import '../services/google_calendar_service.dart';

final gigRepositoryProvider = Provider((ref) => GigRepository.instance);

final gigsProvider = AsyncNotifierProvider<GigsNotifier, List<Gig>>(
  GigsNotifier.new,
);

class GigsNotifier extends AsyncNotifier<List<Gig>> {
  @override
  Future<List<Gig>> build() async {
    return ref.read(gigRepositoryProvider).getAll();
  }

  Future<void> _reloadInvoicesLocal() async {
    await ref.read(invoicesProvider.notifier).reloadLocal();
  }

  Future<void> add(Gig gig) async {
    await ref.read(gigRepositoryProvider).insert(gig);
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'gig',
        entityId: gig.id,
        eventType: 'gig_created',
        payload: {
          'client_id': gig.clientId,
          'fecha': gig.fecha.toIso8601String(),
          'cachet': gig.cachet,
          'facturable': gig.facturable,
          'status': gig.status.dbValue,
        },
      ),
    );
    try {
      await SupabaseService.instance.uploadGigDirect(gig);
    } catch (e) {
      debugPrint('[GigProvider] Supabase gig upload failed: $e');
    }
    ref.invalidate(gigByIdProvider(gig.id));
    ref.invalidateSelf();
    // En caso de reparaciones automáticas (gig↔invoice), refrescar facturas.
    await _reloadInvoicesLocal();
  }

  Future<void> updateGig(Gig gig) async {
    await ref.read(gigRepositoryProvider).update(gig);
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'gig',
        entityId: gig.id,
        eventType: 'gig_updated',
        payload: {
          'client_id': gig.clientId,
          'fecha': gig.fecha.toIso8601String(),
          'cachet': gig.cachet,
          'facturable': gig.facturable,
          'status': gig.status.dbValue,
          'invoice_id': gig.invoiceId,
        },
      ),
    );
    try {
      final updated = await ref.read(gigRepositoryProvider).getById(gig.id);
      if (updated != null) {
        await SupabaseService.instance.uploadGigDirect(updated);
      }
    } catch (e) {
      debugPrint('[GigProvider] Supabase gig update failed: $e');
    }
    ref.invalidate(gigByIdProvider(gig.id));
    ref.invalidateSelf();
    await _reloadInvoicesLocal();
  }

  Future<void> updateStatus(String id, GigStatus status) async {
    final repository = ref.read(gigRepositoryProvider);
    final previous = await repository.getById(id);
    final previousInvoice = await ref
        .read(invoiceRepositoryProvider)
        .getByGigId(id);
    await repository.updateStatus(id, status);
    final updatedGig = await repository.getById(id);
    final invoice = await ref.read(invoiceRepositoryProvider).getByGigId(id);
    try {
      if (invoice != null && previousInvoice == null) {
        await SupabaseService.instance.uploadInvoices([invoice]);
      }
      if (updatedGig != null) {
        await SupabaseService.instance.uploadGigDirect(updatedGig);
      }
    } catch (e) {
      debugPrint('[GigProvider] Supabase status sync failed: $e');
    }
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'gig',
        entityId: id,
        eventType: 'gig_status_changed',
        payload: {
          'from': previous?.status.dbValue,
          'to': status.dbValue,
          'invoice_id': previous?.invoiceId,
        },
      ),
    );
    ref.invalidate(gigByIdProvider(id));
    ref.invalidateSelf();
    // Si el status implica factura, el repositorio puede haber creado una.
    await _reloadInvoicesLocal();
  }

  Future<void> linkInvoice(String gigId, String invoiceId) async {
    await ref.read(gigRepositoryProvider).linkInvoice(gigId, invoiceId);
    final gig = await ref.read(gigRepositoryProvider).getById(gigId);
    try {
      if (gig != null) {
        await SupabaseService.instance.uploadGigDirect(gig);
      }
    } catch (e) {
      debugPrint('[GigProvider] Supabase link invoice failed: $e');
    }
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'gig',
        entityId: gigId,
        eventType: 'gig_invoice_linked',
        payload: {'invoice_id': invoiceId},
      ),
    );
    ref.invalidate(gigByIdProvider(gigId));
    ref.invalidateSelf();
    await _reloadInvoicesLocal();
  }

  Future<void> remove(String id) async {
    final gig = await ref.read(gigRepositoryProvider).getById(id);
    // 1. Borrar de SQLite local (fuente de verdad)
    final result = await ref.read(gigRepositoryProvider).deleteBatch({id});
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'gig',
        entityId: id,
        eventType: 'gig_deleted',
        payload: {
          'client_id': gig?.clientId,
          'fecha': gig?.fecha.toIso8601String(),
          'status': gig?.status.dbValue,
        },
      ),
    );

    // 2. Borrar de Supabase (await + queue si falla)
    try {
      await SupabaseService.instance.deleteGigsBatch(
        gigIds: result.deletedGigIds,
        invoiceIds: result.deletedInvoiceIds,
      );
    } catch (e) {
      debugPrint('[GigProvider] Supabase delete failed, queuing: $e');
      for (final invoiceId in result.deletedInvoiceIds) {
        await DatabaseHelper.instance.addPendingDeletion('invoices', invoiceId);
      }
      for (final gigId in result.deletedGigIds) {
        await DatabaseHelper.instance.addPendingDeletion('gigs', gigId);
      }
    }

    // 3. Borrar de Google Calendar (best-effort)
    try {
      await GoogleCalendarService().deleteGig(id);
    } catch (e) {
      debugPrint('[GigProvider] Google Calendar delete failed: $e');
    }

    ref.invalidateSelf();
    ref.invalidate(gigByIdProvider(id));
    await _reloadInvoicesLocal();
  }

  Future<void> bulkUpdateStatus(Set<String> ids, GigStatus status) async {
    if (ids.isEmpty) return;
    await ref.read(gigRepositoryProvider).updateStatusBatch(ids, status);
    ref.invalidateSelf();
    await _reloadInvoicesLocal();
  }

  Future<void> bulkSetFacturable(Set<String> ids, bool facturable) async {
    if (ids.isEmpty) return;
    await ref
        .read(gigRepositoryProvider)
        .updateFacturableBatch(ids, facturable);
    ref.invalidateSelf();
    await _reloadInvoicesLocal();
  }

  Future<void> bulkDelete(Set<String> ids) async {
    if (ids.isEmpty) return;
    final result = await ref.read(gigRepositoryProvider).deleteBatch(ids);

    try {
      await SupabaseService.instance.deleteGigsBatch(
        gigIds: result.deletedGigIds,
        invoiceIds: result.deletedInvoiceIds,
      );
    } catch (e) {
      debugPrint('[GigProvider] Supabase bulk delete failed, queuing: $e');
      for (final invoiceId in result.deletedInvoiceIds) {
        await DatabaseHelper.instance.addPendingDeletion('invoices', invoiceId);
      }
      for (final gigId in result.deletedGigIds) {
        await DatabaseHelper.instance.addPendingDeletion('gigs', gigId);
      }
    }

    try {
      final calendar = GoogleCalendarService();
      for (final gigId in result.deletedGigIds) {
        await calendar.deleteGig(gigId);
      }
    } catch (e) {
      debugPrint('[GigProvider] Google Calendar bulk delete failed: $e');
    }

    ref.invalidateSelf();
    await _reloadInvoicesLocal();
  }
}

final gigByIdProvider = FutureProvider.family<Gig?, String>((ref, id) {
  return ref.read(gigRepositoryProvider).getById(id);
});

final gigsByClientProvider = FutureProvider.family<List<Gig>, String>((
  ref,
  clientId,
) {
  return ref.read(gigRepositoryProvider).getByClientId(clientId);
});

final gigsMonthProvider =
    FutureProvider.family<List<Gig>, ({int year, int month})>((ref, params) {
      return ref
          .read(gigRepositoryProvider)
          .getByMonth(params.year, params.month);
    });

final upcomingGigsProvider = FutureProvider<List<Gig>>((ref) {
  return ref.read(gigRepositoryProvider).getUpcoming();
});

final recentGigsProvider = FutureProvider<List<Gig>>((ref) {
  return ref.read(gigRepositoryProvider).getRecent();
});
