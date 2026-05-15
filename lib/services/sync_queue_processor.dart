import 'package:flutter/foundation.dart';
import '../models/sync_queue_item.dart';
import '../repositories/sync_queue_repository.dart';
import 'supabase_service.dart';

class SyncQueueProcessor {
  static final SyncQueueProcessor instance = SyncQueueProcessor._();
  SyncQueueProcessor._();

  bool _isProcessing = false;

  Future<void> processPending({String reason = 'manual'}) async {
    final watch = Stopwatch()..start();
    if (_isProcessing) {
      debugPrint('[SyncQueue] skip inFlight ($reason)');
      return;
    }
    if (!SupabaseService.instance.isAuthenticated) return;

    _isProcessing = true;
    final repo = SyncQueueRepository.instance;
    var processed = 0;
    var failed = 0;
    try {
      final pending = await repo.pending();
      if (pending.isEmpty) {
        if (reason != 'periodic_retry') {
          debugPrint(
            '[SyncQueue] empty ($reason) time=${watch.elapsedMilliseconds} ms',
          );
        }
        return;
      }

      debugPrint('[SyncQueue] Processing ${pending.length} items ($reason)');
      for (final item in pending) {
        try {
          await SupabaseService.instance.processQueuedItem(item);
          await repo.remove(item.id);
          processed++;
          debugPrint(
            '[SyncQueue] OK ${item.operation.dbValue} ${item.entityType.dbValue}/${item.entityId}',
          );
        } catch (e) {
          await repo.markFailed(item.id, e);
          failed++;
          debugPrint(
            '[SyncQueue] FAIL ${item.operation.dbValue} ${item.entityType.dbValue}/${item.entityId}: $e',
          );
        }
      }
    } finally {
      if (reason != 'periodic_retry' || processed > 0 || failed > 0) {
        debugPrint(
          '[SyncQueue] done ($reason) processed=$processed failed=$failed time=${watch.elapsedMilliseconds} ms',
        );
      }
      _isProcessing = false;
    }
  }
}
