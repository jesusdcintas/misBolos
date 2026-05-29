import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_event.dart';
import '../models/invoice.dart';
import '../models/sync_queue_item.dart';
import '../repositories/app_event_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/sync_queue_repository.dart';
import '../core/services/drive_document_sync_service.dart';
import '../core/services/google_drive_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_queue_processor.dart';
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
  bool _manualRenumberInProgress = false;
  static const Duration _realtimeDebounceDelay = Duration(milliseconds: 700);
  static const Duration _localEchoWindow = Duration(seconds: 3);

  @override
  Future<List<Invoice>> build() async {
    _startRealtimeIfNeeded();
    ref.onDispose(_disposeRealtime);
    await SyncQueueProcessor.instance.processPending(
      reason: 'invoices_provider',
    );
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

  void _logInvoiceNumberChange({
    required String origin,
    required String invoiceId,
    required int? oldNumber,
    required int newNumber,
  }) {
    const allowedOrigins = {'create_invoice', 'manual_renumber'};
    final prefix = allowedOrigins.contains(origin)
        ? '[InvoiceNumber]'
        : '[InvoiceNumber][WARNING]';
    debugPrint(
      '$prefix origin=$origin invoice_id=$invoiceId '
      'old_number=$oldNumber new_number=$newNumber',
    );
  }

  Future<void> reloadLocal({bool force = false}) async {
    if (_manualRenumberInProgress && !force) {
      debugPrint('[InvoicesSync] reload local omitido: reenumeración en curso');
      return;
    }
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
        driveFileId: m['drive_file_id']?.toString(),
        driveFileUrl: m['drive_file_url']?.toString(),
        driveSyncedAt: m['drive_synced_at'] != null
            ? DateTime.tryParse(m['drive_synced_at'].toString())
            : null,
        driveUploadedAt: m['drive_uploaded_at'] != null
            ? DateTime.tryParse(m['drive_uploaded_at'].toString())
            : null,
        driveSyncStatus: (m['drive_sync_status']?.toString().trim().isNotEmpty ??
                false)
            ? m['drive_sync_status'].toString()
            : (m['drive_file_id']?.toString().trim().isNotEmpty ?? false)
            ? 'uploaded'
            : 'pending',
        status: status,
        createdAt: createdAt,
        updatedAt:
            DateTime.tryParse((m['updated_at'] ?? '').toString()) ?? createdAt,
        deletedAt: m['deleted_at'] != null
            ? DateTime.tryParse(m['deleted_at'].toString())
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _remoteNumberChangeSource(Invoice remote) async {
    final local = await ref.read(invoiceRepositoryProvider).getById(remote.id);
    if (local == null || local.numero == remote.numero) return null;
    final authorized = await SupabaseService.instance
        .hasAuthorizedInvoiceNumberChange(
          invoiceId: remote.id,
          newNumber: remote.numero,
        );
    if (authorized) return InvoiceNumberChangeSource.manualRenumber;

    debugPrint(
      '[InvoiceNumber][CRITICAL] remoto intentó cambiar número sin auditoría '
      'invoice_id=${remote.id} local=${local.numero} remote=${remote.numero}',
    );
    debugPrintStack(stackTrace: StackTrace.current);
    return null;
  }

  Future<void> _handleRealtimeEvent(PostgresChangePayload payload) async {
    if (_manualRenumberInProgress) {
      debugPrint('[InvoicesSync] realtime ignorado: reenumeración en curso');
      return;
    }

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
      if (invoice.numero <= 0) {
        debugPrint(
          '[InvoicesSync] realtime ignorado por número temporal invoice_id=${invoice.id}',
        );
        return;
      }
      final source = await _remoteNumberChangeSource(invoice);
      await ref
          .read(invoiceRepositoryProvider)
          .upsert(invoice, allowedNumberChangeSource: source);
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
    if (_manualRenumberInProgress) {
      debugPrint(
        '[InvoicesSync] refresh omitido ($reason): reenumeración en curso',
      );
      return;
    }

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
    await SyncQueueProcessor.instance.processPending(
      reason: 'invoice_refresh_$reason',
    );
    final repository = ref.read(invoiceRepositoryProvider);
    final cloudInvoices = await SupabaseService.instance.downloadInvoices();

    for (final invoice in cloudInvoices) {
      if (invoice.numero <= 0) {
        debugPrint(
          '[InvoicesSync] factura remota omitida por número temporal invoice_id=${invoice.id}',
        );
        continue;
      }
      if (invoice.deletedAt != null) {
        await repository.delete(invoice.id);
        continue;
      }

      final hasPending = await SyncQueueRepository.instance.hasPending(
        'invoice',
        invoice.id,
      );
      if (hasPending) continue;

      final local = await repository.getById(invoice.id);
      if (local == null || invoice.updatedAt.isAfter(local.updatedAt)) {
        final source = await _remoteNumberChangeSource(invoice);
        await repository.upsert(invoice, allowedNumberChangeSource: source);
      }
    }

    final cloudIds = cloudInvoices.map((i) => i.id).toSet();
    final localInvoices = await repository.getAll();
    for (final local in localInvoices) {
      final hasPending = await SyncQueueRepository.instance.hasPending(
        'invoice',
        local.id,
      );
      if (!cloudIds.contains(local.id) && !hasPending) {
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
    _logInvoiceNumberChange(
      origin: 'create_invoice',
      invoiceId: invoice.id,
      oldNumber: null,
      newNumber: invoice.numero,
    );
    final saved = await ref.read(invoiceRepositoryProvider).getById(invoice.id);
    await SyncQueueRepository.instance.enqueue(
      entityType: SyncEntityType.invoice,
      entityId: invoice.id,
      operation: SyncOperation.create,
      payload: (saved ?? invoice).toMap(),
    );
    await SyncQueueProcessor.instance.processPending(reason: 'invoice_add');
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
    _logInvoiceNumberChange(
      origin: 'create_invoice',
      invoiceId: invoice.id,
      oldNumber: null,
      newNumber: invoice.numero,
    );
    final savedInvoice = await repository.getById(invoice.id);
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
    await SyncQueueRepository.instance.enqueue(
      entityType: SyncEntityType.invoice,
      entityId: invoice.id,
      operation: SyncOperation.create,
      payload: (savedInvoice ?? invoice).toMap(),
    );
    if (gig != null) {
      await SyncQueueRepository.instance.enqueue(
        entityType: SyncEntityType.gig,
        entityId: gig.id,
        operation: SyncOperation.update,
        payload: gig.toMap(),
      );
    }
    await SyncQueueProcessor.instance.processPending(
      reason: 'invoice_add_link',
    );
    debugPrint(
      '[InvoiceProvider] createInvoiceFromGig done invoice_id=${invoice.id} gig_id=${invoice.gigId}',
    );
    ref.invalidate(gigByIdProvider(invoice.gigId));
    ref.invalidate(gigsProvider);
    await reloadLocal();
    final invoiceForDrive = savedInvoice ?? invoice;
    try {
      if (invoiceForDrive.driveFileId?.trim().isNotEmpty == true) {
        debugPrint(
          '[DriveAutoUpload] enqueue skipped: already has drive_file_id entity=invoice/${invoiceForDrive.id}',
        );
        return;
      }
      await DriveDocumentSyncService.instance.enqueuePendingUpload(
        entityType: 'invoice',
        entityId: invoiceForDrive.id,
        targetFolderType: 'FACTURAS',
        documentType: 'invoice_pdf',
        mimeType: 'application/pdf',
        driveFileId: invoiceForDrive.driveFileId,
        logicalPath: 'FACTURAS/${invoiceForDrive.id}',
      );
      debugPrint(
        '[DriveAutoUpload] queued invoice/${invoiceForDrive.id} after create',
      );
      unawaited(
        DriveDocumentSyncService.instance.processPendingUploads(
          reason: 'invoice_created',
        ),
      );
    } catch (e) {
      debugPrint(
        '[DriveAutoUpload] invoice/${invoiceForDrive.id} queue failed: $e',
      );
    }
  }

  Future<void> updateInvoice(Invoice invoice) async {
    _markLocalMutation();
    final repository = ref.read(invoiceRepositoryProvider);
    final previous = await repository.getById(invoice.id);
    if (previous != null && previous.numero != invoice.numero) {
      _logInvoiceNumberChange(
        origin: 'invoice_update',
        invoiceId: invoice.id,
        oldNumber: previous.numero,
        newNumber: invoice.numero,
      );
      throw StateError(
        'El número fiscal solo puede cambiar desde la reenumeración manual.',
      );
    }
    await repository.update(invoice);
    final saved = await repository.getById(invoice.id);
    await SyncQueueRepository.instance.enqueue(
      entityType: SyncEntityType.invoice,
      entityId: invoice.id,
      operation: SyncOperation.update,
      payload: (saved ?? invoice).toMap(),
    );
    await SyncQueueProcessor.instance.processPending(reason: 'invoice_update');
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
      await SyncQueueRepository.instance.enqueue(
        entityType: SyncEntityType.invoice,
        entityId: invoice.id,
        operation: SyncOperation.statusChange,
        payload: invoice.toMap(),
      );
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
        await SyncQueueRepository.instance.enqueue(
          entityType: SyncEntityType.gig,
          entityId: gig.id,
          operation: SyncOperation.statusChange,
          payload: gig.toMap(),
        );
      }
      await SyncQueueProcessor.instance.processPending(
        reason: 'invoice_status',
      );
      ref.invalidate(gigByIdProvider(invoice.gigId));
      ref.invalidate(gigsProvider);
    }
    await reloadLocal();
  }

  Future<void> remove(String id, {bool deleteFromDrive = false}) async {
    _markLocalMutation();
    final invoice = await ref
        .read(invoiceRepositoryProvider)
        .deleteAndUnlinkGig(id);
    if (deleteFromDrive && invoice?.driveFileId?.trim().isNotEmpty == true) {
      try {
        await GoogleDriveService.instance.trashFile(invoice!.driveFileId!);
      } catch (e) {
        debugPrint(
          '[InvoiceProvider] No se pudo enviar factura a papelera Drive: $e',
        );
      }
    }
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
    final deletedInvoice = await ref
        .read(invoiceRepositoryProvider)
        .getById(id);
    if (deletedInvoice != null) {
      await SyncQueueRepository.instance.enqueue(
        entityType: SyncEntityType.invoice,
        entityId: id,
        operation: SyncOperation.delete,
        payload: deletedInvoice.toMap(),
      );
    }
    if (invoice != null) {
      final gig = await GigRepository.instance.getById(invoice.gigId);
      if (gig != null) {
        await SyncQueueRepository.instance.enqueue(
          entityType: SyncEntityType.gig,
          entityId: gig.id,
          operation: SyncOperation.update,
          payload: gig.toMap(),
        );
      }
    }
    await SyncQueueProcessor.instance.processPending(reason: 'invoice_delete');
    await DriveDocumentSyncService.instance.removeQueueForEntity(
      entityType: 'invoice',
      entityId: id,
    );
    await reloadLocal();
    if (invoice != null) {
      ref.invalidate(gigByIdProvider(invoice.gigId));
      ref.invalidate(gigsProvider);
    }
  }

  Future<void> renumberInvoicesManually({
    required int fiscalYear,
    required Map<String, int> newNumbersByInvoiceId,
    String? reason,
  }) async {
    final userId = SupabaseService.instance.userId;
    if (userId == null || userId.isEmpty) {
      throw StateError('Debes iniciar sesión para reenumerar facturas.');
    }

    final repository = ref.read(invoiceRepositoryProvider);
    ManualRenumberResult? result;
    _manualRenumberInProgress = true;
    _markLocalMutation();
    try {
      result = await repository.renumberInvoicesManually(
        fiscalYear: fiscalYear,
        newNumbersByInvoiceId: newNumbersByInvoiceId,
        userId: userId,
        reason: reason,
      );
      final hasTemporaryNumber = result.updatedInvoices.any(
        (invoice) => invoice.numero <= 0,
      );
      if (hasTemporaryNumber) {
        throw StateError(
          'Error crítico: la reenumeración devolvió números temporales.',
        );
      }

      await SupabaseService.instance.renumberInvoices(
        result.updatedInvoices,
        reason: reason,
      );

      final createdAt = DateTime.now().toIso8601String();
      for (final change in result.changes) {
        _logInvoiceNumberChange(
          origin: 'manual_renumber',
          invoiceId: change.invoiceId,
          oldNumber: change.oldNumber,
          newNumber: change.newNumber,
        );
        await AppEventRepository.instance.insert(
          AppEvent(
            entityType: 'invoice',
            entityId: change.invoiceId,
            eventType: 'invoice_manual_renumbered',
            payload: {
              'invoice_id': change.invoiceId,
              'old_number': change.oldNumber,
              'new_number': change.newNumber,
              'user_id': userId,
              'created_at': createdAt,
              'reason': reason,
            },
          ),
        );
      }
    } catch (error) {
      if (result != null) {
        final rollbackNumbers = {
          for (final change in result.changes)
            change.invoiceId: change.oldNumber,
        };
        try {
          await repository.renumberInvoicesManually(
            fiscalYear: fiscalYear,
            newNumbersByInvoiceId: rollbackNumbers,
            userId: userId,
            reason: 'rollback_after_failed_remote_renumber',
          );
          debugPrint(
            '[InvoiceNumber] rollback local aplicado tras fallo: $error',
          );
        } catch (rollbackError) {
          debugPrint(
            '[InvoiceNumber][WARNING] rollback local falló: $rollbackError',
          );
        }
      }
      rethrow;
    } finally {
      _manualRenumberInProgress = false;
      await reloadLocal(force: true);
    }
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

final invoicesByFiscalYearProvider = FutureProvider.family<List<Invoice>, int>((
  ref,
  year,
) {
  ref.watch(invoicesProvider);
  return ref.read(invoiceRepositoryProvider).getByFiscalYear(year);
});
