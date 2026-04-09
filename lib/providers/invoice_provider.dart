import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/invoice.dart';
import '../repositories/invoice_repository.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';

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
    ref.invalidateSelf();
  }

  Future<void> updateInvoice(Invoice invoice) async {
    await ref.read(invoiceRepositoryProvider).update(invoice);
    ref.invalidateSelf();
  }

  Future<void> updateStatus(String id, InvoiceStatus status) async {
    await ref.read(invoiceRepositoryProvider).updateStatus(id, status);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(invoiceRepositoryProvider).delete(id);
    try {
      await SupabaseService.instance.deleteInvoice(id);
    } catch (e) {
      debugPrint('[InvoiceProvider] Supabase delete failed, queuing: $e');
      await DatabaseHelper.instance.addPendingDeletion('invoices', id);
    }
    ref.invalidateSelf();
  }

  Future<void> updateNumber(String id, int newNumber) async {
    await ref.read(invoiceRepositoryProvider).updateNumber(id, newNumber);
    ref.invalidateSelf();
  }

  Future<void> renumberAll(int startFrom) async {
    await ref.read(invoiceRepositoryProvider).renumberAll(startFrom);
    ref.invalidateSelf();
  }

  Future<bool> isNumberTaken(int number, {String? excludeId}) async {
    return ref.read(invoiceRepositoryProvider).isNumberTaken(number, excludeId: excludeId);
  }
}

final invoiceByIdProvider = FutureProvider.family<Invoice?, String>((ref, id) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getById(id);
});

final invoiceByGigProvider = FutureProvider.family<Invoice?, String>((ref, gigId) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getByGigId(gigId);
});

final invoicesByStatusProvider = FutureProvider.family<List<Invoice>, InvoiceStatus>((ref, status) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getByStatus(status);
});

final invoicesByClientProvider = FutureProvider.family<List<Invoice>, String>((ref, clientId) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getByClientId(clientId);
});

final nextInvoiceNumberProvider = FutureProvider<int>((ref) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getNextNumber();
});
