import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_event.dart';
import '../models/invoice.dart';
import '../repositories/app_event_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_repository.dart';
import '../database/database_helper.dart';
import '../services/import_service.dart';
import '../services/supabase_service.dart';
import 'gig_provider.dart';

final invoiceRepositoryProvider = Provider((ref) => InvoiceRepository.instance);

final invoicesProvider = AsyncNotifierProvider<InvoicesNotifier, List<Invoice>>(
  InvoicesNotifier.new,
);

class InvoicesNotifier extends AsyncNotifier<List<Invoice>> {
  RealtimeChannel? _invoicesChannel;
  bool _realtimeStarted = false;
  DateTime? _lastRemoteRefreshAt;
  Future<void>? _refreshInFlight;
  Timer? _realtimeRefreshDebounce;
  DateTime? _lastLocalMutationAt;
  static const Duration _realtimeDebounceDelay = Duration(milliseconds: 700);
  static const Duration _localEchoWindow = Duration(seconds: 3);

  @override
  Future<List<Invoice>> build() async {
    _startRealtimeIfNeeded();
    ref.onDispose(_disposeRealtime);
    return ref.read(invoiceRepositoryProvider).getAll();
  }

  void _startRealtimeIfNeeded() {
    if (_realtimeStarted) return;
    _realtimeStarted = true;

    final supabase = SupabaseService.instance;
    if (!supabase.isAuthenticated || supabase.userId == null) {
      debugPrint('[InvoicesSync] Realtime no iniciado: sin sesión');
      return;
    }

    final client = Supabase.instance.client;
    _invoicesChannel = client
        .channel('public:invoices:user:${supabase.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'invoices',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: supabase.userId!,
          ),
          callback: _handleRealtimeEvent,
        )
        .subscribe();

    debugPrint('[InvoicesSync] Realtime suscrito (invoices)');
  }

  void _disposeRealtime() {
    final channel = _invoicesChannel;
    _invoicesChannel = null;
    _realtimeStarted = false;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
      debugPrint('[InvoicesSync] Realtime desuscrito (invoices)');
    }
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = null;
  }

  void _markLocalMutation() {
    _lastLocalMutationAt = DateTime.now().toUtc();
  }

  Future<void> reloadLocal() async {
    final invoices = await ref.read(invoiceRepositoryProvider).getAll();
    state = AsyncData(invoices);
  }

  bool _isLikelyLocalEcho(PostgresChangePayload payload) {
    final now = DateTime.now().toUtc();
    final localAt = _lastLocalMutationAt;
    if (localAt == null || now.difference(localAt) > _localEchoWindow) {
      return false;
    }

    final record = payload.newRecord.isNotEmpty
        ? payload.newRecord
        : payload.oldRecord;
    final updatedBy = record['updated_by']?.toString();
    final deviceId = record['device_id']?.toString();
    final changedAtRaw =
        record['updated_at'] ?? record['changed_at'] ?? record['created_at'];
    final changedAt = changedAtRaw == null
        ? null
        : DateTime.tryParse(changedAtRaw.toString())?.toUtc();

    final bySelf =
        updatedBy != null && updatedBy == SupabaseService.instance.userId;
    final sameDevice = deviceId != null && deviceId.isNotEmpty;
    final veryRecent =
        changedAt != null && now.difference(changedAt).abs() < _localEchoWindow;

    return bySelf || sameDevice || veryRecent;
  }

  Invoice? _invoiceFromRealtimeRecord(Map<String, dynamic> m) {
    final id = m['id']?.toString();
    final numeroRaw = m['numero'];
    final fechaRaw = m['fecha'] ?? m['fecha_emision'];
    final clientId = m['client_id']?.toString();
    final gigId = m['gig_id']?.toString();
    final itemsRaw = m['items'];
    if (id == null ||
        numeroRaw == null ||
        fechaRaw == null ||
        clientId == null ||
        gigId == null ||
        itemsRaw == null) {
      return null;
    }

    try {
      final status = InvoiceStatusExtension.fromDb(
        (m['status'] ?? 'borrador').toString(),
      );
      final createdAt =
          DateTime.tryParse((m['created_at'] ?? '').toString()) ??
          DateTime.now();

      List<InvoiceLineItem> items = [];
      if (itemsRaw is List) {
        items = itemsRaw
            .whereType<Map>()
            .map((e) => InvoiceLineItem.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      }

      final ivaRate =
          ((m['iva_rate'] as num?)?.toDouble()) ??
          (((m['iva_porcentaje'] as num?)?.toDouble() ?? 21) / 100);
      final irpfRate =
          ((m['irpf_rate'] as num?)?.toDouble()) ??
          (((m['irpf_porcentaje'] as num?)?.toDouble() ?? 0) / 100);

      return Invoice(
        id: id,
        numero: int.tryParse(numeroRaw.toString()) ?? 0,
        fecha: DateTime.parse(fechaRaw.toString()),
        clientId: clientId,
        gigId: gigId,
        items: items,
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
        ivaRate: ivaRate,
        ivaAmount:
            (m['iva_amount'] as num?)?.toDouble() ??
            (m['iva_importe'] as num?)?.toDouble() ??
            0,
        irpfRate: irpfRate,
        irpfAmount:
            (m['irpf_amount'] as num?)?.toDouble() ??
            (m['irpf_importe'] as num?)?.toDouble() ??
            0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        status: status,
        createdAt: createdAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleRealtimeEvent(PostgresChangePayload payload) async {
    if (_isLikelyLocalEcho(payload)) {
      return;
    }

    final event = payload.eventType;
    final id =
        (payload.newRecord['id'] ?? payload.oldRecord['id'])?.toString() ??
        'unknown';

    if (event == PostgresChangeEvent.update) {
      final invoice = _invoiceFromRealtimeRecord(payload.newRecord);
      if (invoice == null) return;
      await ref.read(invoiceRepositoryProvider).upsert(invoice);
      await GigRepository.instance.repairStatusesFromInvoices([invoice]);
      ref.invalidate(gigByIdProvider(invoice.gigId));
      ref.invalidate(gigsProvider);
      await reloadLocal();
      return;
    }

    if (_refreshInFlight != null) {
      return;
    }

    if (event == PostgresChangeEvent.insert ||
        event == PostgresChangeEvent.delete) {
      _realtimeRefreshDebounce?.cancel();
      _realtimeRefreshDebounce = Timer(_realtimeDebounceDelay, () {
        unawaited(
          refreshFromCloud(reason: 'realtime_${event.name}', force: true),
        );
      });
      debugPrint(
        '[InvoicesSync] Realtime ${event.name.toUpperCase()} invoice_id=$id',
      );
    }
  }

  Future<void> refreshFromCloud({
    String reason = 'manual',
    bool force = false,
  }) async {
    _startRealtimeIfNeeded();
    final supabase = SupabaseService.instance;
    if (!supabase.isAuthenticated) {
      debugPrint('[InvoicesSync] refresh omitido ($reason): sin sesión');
      return;
    }

    if (!force && _lastRemoteRefreshAt != null) {
      final elapsed = DateTime.now().difference(_lastRemoteRefreshAt!);
      if (elapsed.inMilliseconds < 1200) {
        debugPrint('[InvoicesSync] refresh omitido ($reason): throttle');
        return;
      }
    }

    if (_refreshInFlight != null) {
      debugPrint('[InvoicesSync] refresh reutiliza inFlight ($reason)');
      return _refreshInFlight;
    }

    _refreshInFlight = _doRefreshFromCloud(reason);
    try {
      await _refreshInFlight;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> _doRefreshFromCloud(String reason) async {
    debugPrint('[InvoicesSync] refresh remoto start ($reason)');
    final repository = ref.read(invoiceRepositoryProvider);
    final cloudInvoices = await SupabaseService.instance.downloadInvoices();

    for (final invoice in cloudInvoices) {
      await repository.upsert(invoice);
    }

    final cloudIds = cloudInvoices.map((i) => i.id).toSet();
    final localInvoices = await repository.getAll();
    for (final local in localInvoices) {
      if (!cloudIds.contains(local.id)) {
        await repository.delete(local.id);
      }
    }

    await GigRepository.instance.repairStatusesFromInvoices(cloudInvoices);
    _lastRemoteRefreshAt = DateTime.now();
    ref.invalidate(gigsProvider);
    await reloadLocal();
    debugPrint('[InvoicesSync] refresh remoto done ($reason)');
  }

  Future<void> add(Invoice invoice) async {
    _markLocalMutation();
    debugPrint(
      '[InvoiceProvider] createInvoiceFromGig start invoice_id=${invoice.id} gig_id=${invoice.gigId}',
    );
    await ref.read(invoiceRepositoryProvider).insert(invoice);
    try {
      await SupabaseService.instance.uploadInvoices([invoice]);
    } catch (e) {
      debugPrint('[InvoiceProvider] Supabase create upload failed: $e');
    }
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
    debugPrint(
      '[InvoiceProvider] createInvoiceFromGig done invoice_id=${invoice.id} gig_id=${invoice.gigId}',
    );
    await reloadLocal();
  }

  Future<void> addAndLinkToGig(Invoice invoice) async {
    _markLocalMutation();
    debugPrint(
      '[InvoiceProvider] createInvoiceFromGig start invoice_id=${invoice.id} gig_id=${invoice.gigId}',
    );
    final repository = ref.read(invoiceRepositoryProvider);
    await repository.insertAndLinkGig(invoice);
    final gig = await GigRepository.instance.getById(invoice.gigId);
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
    try {
      await SupabaseService.instance.uploadInvoices([invoice]);
      if (gig != null) {
        await SupabaseService.instance.uploadGigDirect(gig);
      }
    } catch (e) {
      debugPrint('[InvoiceProvider] Supabase create/link upload failed: $e');
    }
    debugPrint(
      '[InvoiceProvider] createInvoiceFromGig done invoice_id=${invoice.id} gig_id=${invoice.gigId}',
    );
    ref.invalidate(gigByIdProvider(invoice.gigId));
    ref.invalidate(gigsProvider);
    await reloadLocal();
  }

  Future<void> updateInvoice(Invoice invoice) async {
    _markLocalMutation();
    await ref.read(invoiceRepositoryProvider).update(invoice);
    try {
      await SupabaseService.instance.uploadInvoices([invoice]);
    } catch (e) {
      debugPrint('[InvoiceProvider] Supabase invoice update failed: $e');
    }
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
    await reloadLocal();
  }

  Future<void> updateStatus(String id, InvoiceStatus status) async {
    _markLocalMutation();
    final repository = ref.read(invoiceRepositoryProvider);
    final previous = await repository.getById(id);
    await repository.updateStatus(id, status);
    final invoice = await repository.getById(id);
    if (invoice != null) {
      try {
        await SupabaseService.instance.uploadInvoices([invoice]);
      } catch (e) {
        debugPrint('[InvoiceProvider] Supabase status upload failed: $e');
      }
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
      final gig = await GigRepository.instance.getById(invoice.gigId);
      if (gig != null) {
        try {
          await SupabaseService.instance.uploadGigDirect(gig);
        } catch (e) {
          debugPrint('[InvoiceProvider] Supabase gig status upload failed: $e');
        }
      }
      ref.invalidate(gigByIdProvider(invoice.gigId));
      ref.invalidate(gigsProvider);
    }
    await reloadLocal();
  }

  Future<void> remove(String id) async {
    _markLocalMutation();
    final invoice = await ref
        .read(invoiceRepositoryProvider)
        .deleteAndUnlinkGig(id);
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
      if (invoice != null) {
        final gig = await GigRepository.instance.getById(invoice.gigId);
        if (gig != null) {
          await SupabaseService.instance.uploadGigDirect(gig);
        }
      }
    } catch (e) {
      debugPrint('[InvoiceProvider] Supabase delete failed, queuing: $e');
      await DatabaseHelper.instance.addPendingDeletion('invoices', id);
    }
    await reloadLocal();
    if (invoice != null) {
      ref.invalidate(gigByIdProvider(invoice.gigId));
      ref.invalidate(gigsProvider);
    }
  }

  Future<void> updateNumber(String id, int newNumber) async {
    _markLocalMutation();
    final repository = ref.read(invoiceRepositoryProvider);
    final previous = await repository.getById(id);
    await repository.updateNumber(id, newNumber);
    final invoice = await repository.getById(id);
    if (invoice != null) {
      try {
        await SupabaseService.instance.uploadInvoices([invoice]);
      } catch (e) {
        debugPrint('[InvoiceProvider] Supabase number upload failed: $e');
      }
    }
    await AppEventRepository.instance.insert(
      AppEvent(
        entityType: 'invoice',
        entityId: id,
        eventType: 'invoice_number_changed',
        payload: {'from': previous?.numero, 'to': newNumber},
      ),
    );
    await reloadLocal();
  }

  Future<void> renumberYear(int year) async {
    _markLocalMutation();
    final invoices = await ref
        .read(invoiceRepositoryProvider)
        .renumberYear(year, startFrom: 1);
    await SupabaseService.instance.renumberInvoices(invoices);
    await refreshFromCloud(reason: 'local_renumber_year', force: true);
  }

  Future<List<InvoiceGapPreviewItem>> previewCloseGapsYear(
    int year, {
    bool includeDrafts = false,
  }) {
    return ref
        .read(invoiceRepositoryProvider)
        .previewCloseGapsYear(year, includeDrafts: includeDrafts);
  }

  Future<void> closeGapsYear(int year, {bool includeDrafts = false}) async {
    _markLocalMutation();
    final invoices = await ref
        .read(invoiceRepositoryProvider)
        .closeGapsYear(year, includeDrafts: includeDrafts);
    await SupabaseService.instance.renumberInvoices(invoices);
    await refreshFromCloud(reason: 'local_close_gaps_year', force: true);
  }

  Future<bool> isNumberTaken(
    int number, {
    required int year,
    String? excludeId,
  }) async {
    return ref
        .read(invoiceRepositoryProvider)
        .isNumberTaken(number, year: year, excludeId: excludeId);
  }

  Future<int> applyExcelNumberingPreview(
    int year,
    List<ExcelInvoiceNumberingPreviewItem> preview,
  ) async {
    _markLocalMutation();
    final updated = await ImportService.applyNumberingFromExcelPreview(
      year: year,
      preview: preview,
    );
    final repo = ref.read(invoiceRepositoryProvider);
    final all = await repo.getAll();
    final targetIds = preview.map((p) => p.invoiceId).toSet();
    final affected = all.where((i) => targetIds.contains(i.id)).toList();
    await SupabaseService.instance.renumberInvoices(affected);
    await refreshFromCloud(reason: 'local_apply_excel_numbering', force: true);
    return updated;
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

final nextInvoiceNumberProvider = FutureProvider.family<int, int>((ref, year) {
  // Escuchar cambios en invoicesProvider para refrescar automáticamente
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getNextNumberForYear(year);
});
