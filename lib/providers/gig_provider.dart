import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_event.dart';
import '../models/gig.dart';
import '../repositories/app_event_repository.dart';
import '../repositories/gig_repository.dart';
import '../repositories/sync_queue_repository.dart';
import 'invoice_provider.dart';
import '../database/database_helper.dart';
import '../core/services/drive_document_sync_service.dart';
import '../core/services/google_drive_service.dart';
import '../services/google_calendar_service.dart';
import '../services/sync_queue_processor.dart';
import '../models/sync_queue_item.dart';

final gigRepositoryProvider = Provider((ref) => GigRepository.instance);

final gigsProvider = AsyncNotifierProvider<GigsNotifier, List<Gig>>(
  GigsNotifier.new,
);

class GigsNotifier extends AsyncNotifier<List<Gig>> {
  @override
  Future<List<Gig>> build() async {
    await SyncQueueProcessor.instance.processPending(reason: 'gigs_provider');
    return ref.read(gigRepositoryProvider).getAll();
  }

  Future<void> _reloadInvoicesLocal() async {
    await ref.read(invoicesProvider.notifier).reloadLocal();
  }

  Future<void> add(Gig gig) async {
    await ref.read(gigRepositoryProvider).insert(gig);
    final saved = await ref.read(gigRepositoryProvider).getById(gig.id) ?? gig;
    await SyncQueueRepository.instance.enqueue(
      entityType: SyncEntityType.gig,
      entityId: saved.id,
      operation: SyncOperation.create,
      payload: saved.toMap(),
    );
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
    await SyncQueueProcessor.instance.processPending(reason: 'gig_add');
    ref.invalidate(gigByIdProvider(gig.id));
    ref.invalidateSelf();
    // En caso de reparaciones automáticas (gig↔invoice), refrescar facturas.
    await _reloadInvoicesLocal();
  }

  Future<void> updateGig(Gig gig) async {
    await ref.read(gigRepositoryProvider).update(gig);
    final saved = await ref.read(gigRepositoryProvider).getById(gig.id) ?? gig;
    await SyncQueueRepository.instance.enqueue(
      entityType: SyncEntityType.gig,
      entityId: saved.id,
      operation: SyncOperation.update,
      payload: saved.toMap(),
    );
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
    await SyncQueueProcessor.instance.processPending(reason: 'gig_update');
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
    if (invoice != null && previousInvoice == null) {
      await SyncQueueRepository.instance.enqueue(
        entityType: SyncEntityType.invoice,
        entityId: invoice.id,
        operation: SyncOperation.create,
        payload: invoice.toMap(),
      );
    }
    if (updatedGig != null) {
      await SyncQueueRepository.instance.enqueue(
        entityType: SyncEntityType.gig,
        entityId: updatedGig.id,
        operation: SyncOperation.statusChange,
        payload: updatedGig.toMap(),
      );
    }
    await SyncQueueProcessor.instance.processPending(reason: 'gig_status');
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
    if (gig != null) {
      await SyncQueueRepository.instance.enqueue(
        entityType: SyncEntityType.gig,
        entityId: gig.id,
        operation: SyncOperation.update,
        payload: gig.toMap(),
      );
    }
    await SyncQueueProcessor.instance.processPending(
      reason: 'gig_link_invoice',
    );
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

  Future<void> remove(String id, {bool deleteFromDrive = false}) async {
    final gig = await ref.read(gigRepositoryProvider).getById(id);
    final linkedInvoice = await ref
        .read(invoiceRepositoryProvider)
        .getByGigId(id);
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

    for (final invoiceId in result.deletedInvoiceIds) {
      final deleted = await ref
          .read(invoiceRepositoryProvider)
          .getById(invoiceId);
      if (deleted != null) {
        await SyncQueueRepository.instance.enqueue(
          entityType: SyncEntityType.invoice,
          entityId: invoiceId,
          operation: SyncOperation.delete,
          payload: deleted.toMap(),
        );
      }
    }
    for (final gigId in result.deletedGigIds) {
      final deleted = await ref.read(gigRepositoryProvider).getById(gigId);
      if (deleted != null) {
        await SyncQueueRepository.instance.enqueue(
          entityType: SyncEntityType.gig,
          entityId: gigId,
          operation: SyncOperation.delete,
          payload: deleted.toMap(),
        );
      }
    }
    await SyncQueueProcessor.instance.processPending(reason: 'gig_delete');
    if (deleteFromDrive) {
      for (final invoiceId in result.deletedInvoiceIds) {
        final deleted = await ref
            .read(invoiceRepositoryProvider)
            .getById(invoiceId);
        if (deleted?.driveFileId?.trim().isNotEmpty == true) {
          try {
            await GoogleDriveService.instance.trashFile(deleted!.driveFileId!);
          } catch (e) {
            debugPrint(
              '[GigProvider] No se pudo enviar factura a papelera Drive: $e',
            );
          }
        }
        await DriveDocumentSyncService.instance.removeQueueForEntity(
          entityType: 'invoice',
          entityId: invoiceId,
        );
      }

      // Fallback si no llegó id en resultado por edge case de datos legacy.
      if (result.deletedInvoiceIds.isEmpty &&
          linkedInvoice?.driveFileId?.trim().isNotEmpty == true) {
        final legacyInvoice = linkedInvoice;
        if (legacyInvoice != null) {
          try {
            await GoogleDriveService.instance.trashFile(
              legacyInvoice.driveFileId!,
            );
          } catch (e) {
            debugPrint(
              '[GigProvider] No se pudo enviar factura legacy a papelera Drive: $e',
            );
          }
          await DriveDocumentSyncService.instance.removeQueueForEntity(
            entityType: 'invoice',
            entityId: legacyInvoice.id,
          );
        }
      }
    }

    // Compatibilidad con la cola antigua de borrados si la cola nueva fallase
    for (final invoiceId in result.deletedInvoiceIds) {
      try {
        final hasPending = await SyncQueueRepository.instance.hasPending(
          'invoice',
          invoiceId,
        );
        if (hasPending) {
          await DatabaseHelper.instance.addPendingDeletion(
            'invoices',
            invoiceId,
          );
        }
      } catch (e) {
        debugPrint('[GigProvider] Pending deletion fallback failed: $e');
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
    for (final id in ids) {
      final gig = await ref.read(gigRepositoryProvider).getById(id);
      if (gig != null) {
        await SyncQueueRepository.instance.enqueue(
          entityType: SyncEntityType.gig,
          entityId: id,
          operation: SyncOperation.statusChange,
          payload: gig.toMap(),
        );
      }
    }
    await SyncQueueProcessor.instance.processPending(reason: 'gig_bulk_status');
    ref.invalidateSelf();
    await _reloadInvoicesLocal();
  }

  Future<void> bulkSetFacturable(Set<String> ids, bool facturable) async {
    if (ids.isEmpty) return;
    await ref
        .read(gigRepositoryProvider)
        .updateFacturableBatch(ids, facturable);
    for (final id in ids) {
      final gig = await ref.read(gigRepositoryProvider).getById(id);
      if (gig != null) {
        await SyncQueueRepository.instance.enqueue(
          entityType: SyncEntityType.gig,
          entityId: id,
          operation: SyncOperation.update,
          payload: gig.toMap(),
        );
      }
    }
    await SyncQueueProcessor.instance.processPending(
      reason: 'gig_bulk_facturable',
    );
    ref.invalidateSelf();
    await _reloadInvoicesLocal();
  }

  Future<void> bulkDelete(
    Set<String> ids, {
    bool deleteFromDrive = false,
  }) async {
    if (ids.isEmpty) return;
    final result = await ref.read(gigRepositoryProvider).deleteBatch(ids);

    for (final invoiceId in result.deletedInvoiceIds) {
      final deleted = await ref
          .read(invoiceRepositoryProvider)
          .getById(invoiceId);
      if (deleted != null) {
        await SyncQueueRepository.instance.enqueue(
          entityType: SyncEntityType.invoice,
          entityId: invoiceId,
          operation: SyncOperation.delete,
          payload: deleted.toMap(),
        );
      }
    }
    for (final gigId in result.deletedGigIds) {
      final deleted = await ref.read(gigRepositoryProvider).getById(gigId);
      if (deleted != null) {
        await SyncQueueRepository.instance.enqueue(
          entityType: SyncEntityType.gig,
          entityId: gigId,
          operation: SyncOperation.delete,
          payload: deleted.toMap(),
        );
      }
    }
    await SyncQueueProcessor.instance.processPending(reason: 'gig_bulk_delete');
    if (deleteFromDrive) {
      for (final invoiceId in result.deletedInvoiceIds) {
        final deleted = await ref
            .read(invoiceRepositoryProvider)
            .getById(invoiceId);
        if (deleted?.driveFileId?.trim().isNotEmpty == true) {
          try {
            await GoogleDriveService.instance.trashFile(deleted!.driveFileId!);
          } catch (e) {
            debugPrint(
              '[GigProvider] No se pudo enviar factura a papelera Drive (bulk): $e',
            );
          }
        }
        await DriveDocumentSyncService.instance.removeQueueForEntity(
          entityType: 'invoice',
          entityId: invoiceId,
        );
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
