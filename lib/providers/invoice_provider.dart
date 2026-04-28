import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_event.dart';
import '../models/invoice.dart';
import '../repositories/app_event_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_repository.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
import 'gig_provider.dart';

final invoiceRepositoryProvider = Provider((ref) => InvoiceRepository.instance);

final invoicesProvider = AsyncNotifierProvider<InvoicesNotifier, List<Invoice>>(
  InvoicesNotifier.new,
);

class InvoicesNotifier extends AsyncNotifier<List<Invoice>> {
  @override
  Future<List<Invoice>> build() async {
    return ref.read(invoiceRepositoryProvider).getAll();
  }

  Future<void> add(Invoice invoice) async {
    await ref.read(invoiceRepositoryProvider).insert(invoice);
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'invoice',
        entityId: invoice.id,
        eventType: 'invoice_created',
        payload: {
          'numero': invoice.numero,
          'client_id': invoice.clientId,
          'gig_id': invoice.gigId,
          'total': invoice.total,
          'status': invoice.status.dbValue,
        },
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> updateInvoice(Invoice invoice) async {
    await ref.read(invoiceRepositoryProvider).update(invoice);
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'invoice',
        entityId: invoice.id,
        eventType: 'invoice_updated',
        payload: {
          'numero': invoice.numero,
          'client_id': invoice.clientId,
          'gig_id': invoice.gigId,
          'total': invoice.total,
          'status': invoice.status.dbValue,
        },
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> updateStatus(String id, InvoiceStatus status) async {
    final repository = ref.read(invoiceRepositoryProvider);
    final previous = await repository.getById(id);
    await repository.updateStatus(id, status);
    final invoice = await repository.getById(id);
    if (invoice != null) {
      await AppEventRepository.instance.insert(
        AppEvent(
          entityType: 'invoice',
          entityId: invoice.id,
          eventType: 'invoice_status_changed',
          payload: {
            'from': previous?.status.dbValue,
            'to': status.dbValue,
            'numero': invoice.numero,
            'gig_id': invoice.gigId,
          },
        ),
      );
      await GigRepository.instance.repairStatusesFromInvoices([invoice]);
      ref.invalidate(gigByIdProvider(invoice.gigId));
      ref.invalidate(gigsProvider);
    }
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final invoice = await ref.read(invoiceRepositoryProvider).getById(id);
    await ref.read(invoiceRepositoryProvider).delete(id);
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'invoice',
        entityId: id,
        eventType: 'invoice_deleted',
        payload: {
          'numero': invoice?.numero,
          'client_id': invoice?.clientId,
          'gig_id': invoice?.gigId,
        },
      ),
    );
    try {
      await SupabaseService.instance.deleteInvoice(id);
    } catch (e) {
      debugPrint('[InvoiceProvider] Supabase delete failed, queuing: $e');
      await DatabaseHelper.instance.addPendingDeletion('invoices', id);
    }
    ref.invalidateSelf();
  }

  Future<void> updateNumber(String id, int newNumber) async {
    final repository = ref.read(invoiceRepositoryProvider);
    final previous = await repository.getById(id);
    await repository.updateNumber(id, newNumber);
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'invoice',
        entityId: id,
        eventType: 'invoice_number_changed',
        payload: {'from': previous?.numero, 'to': newNumber},
      ),
    );
    ref.invalidateSelf();
  }

  Future<void> renumberAll(int startFrom) async {
    await ref.read(invoiceRepositoryProvider).renumberAll(startFrom);
    ref.invalidateSelf();
  }

  Future<bool> isNumberTaken(int number, {String? excludeId}) async {
    return ref
        .read(invoiceRepositoryProvider)
        .isNumberTaken(number, excludeId: excludeId);
  }
}

final invoiceByIdProvider = FutureProvider.family<Invoice?, String>((ref, id) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getById(id);
});

final invoiceByGigProvider = FutureProvider.family<Invoice?, String>((
  ref,
  gigId,
) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getByGigId(gigId);
});

final invoicesByStatusProvider =
    FutureProvider.family<List<Invoice>, InvoiceStatus>((ref, status) {
      // Escuchar cambios en invoicesProvider para refrescar automáticamente
      ref.watch(invoicesProvider);
      return ref.read(invoiceRepositoryProvider).getByStatus(status);
    });

final invoicesByClientProvider = FutureProvider.family<List<Invoice>, String>((
  ref,
  clientId,
) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getByClientId(clientId);
});

final nextInvoiceNumberProvider = FutureProvider<int>((ref) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getNextNumber();
});
