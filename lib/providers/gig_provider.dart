import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gig.dart';
import '../repositories/gig_repository.dart';
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

  Future<void> add(Gig gig) async {
    await ref.read(gigRepositoryProvider).insert(gig);
    ref.invalidate(gigByIdProvider(gig.id));
    ref.invalidateSelf();
  }

  Future<void> updateGig(Gig gig) async {
    await ref.read(gigRepositoryProvider).update(gig);
    ref.invalidate(gigByIdProvider(gig.id));
    ref.invalidateSelf();
  }

  Future<void> updateStatus(String id, GigStatus status) async {
    await ref.read(gigRepositoryProvider).updateStatus(id, status);
    ref.invalidate(gigByIdProvider(id));
    ref.invalidateSelf();
  }

  Future<void> linkInvoice(String gigId, String invoiceId) async {
    await ref.read(gigRepositoryProvider).linkInvoice(gigId, invoiceId);
    ref.invalidate(gigByIdProvider(gigId));
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    // 1. Borrar de SQLite local (fuente de verdad)
    await ref.read(gigRepositoryProvider).delete(id);

    // 2. Borrar de Supabase (await + queue si falla)
    try {
      await SupabaseService.instance.deleteGig(id);
    } catch (e) {
      debugPrint('[GigProvider] Supabase delete failed, queuing: $e');
      await DatabaseHelper.instance.addPendingDeletion('gigs', id);
    }

    // 3. Borrar de Google Calendar (best-effort)
    try {
      await GoogleCalendarService().deleteGig(id);
    } catch (e) {
      debugPrint('[GigProvider] Google Calendar delete failed: $e');
    }

    ref.invalidateSelf();
    ref.invalidate(gigByIdProvider(id));
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
