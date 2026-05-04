import 'package:flutter/foundation.dart';
import '../models/sync_queue_item.dart';
import '../repositories/sync_queue_repository.dart';
import 'supabase_service.dart';

class SyncQueueProcessor {
  static final SyncQueueProcessor instance = SyncQueueProcessor._();
  SyncQueueProcessor._();

  bool _isProcessing = false;

  Future<void> processPending({String reason = 'manual'}) async {
    if (_isProcessing) return;
    if (!SupabaseService.instance.isAuthenticated) return;

    _isProcessing = true;
    final repo = SyncQueueRepository.instance;
    try {
      final pending = await repo.pending();
      if (pending.isEmpty) return;

      debugPrint('[SyncQueue] Processing ${pending.length} items ($reason)');
      for (final item in pending) {
        try {
          await SupabaseService.instance.processQueuedItem(item);
          await repo.remove(item.id);
          debugPrint(
            '[SyncQueue] OK ${item.operation.dbValue} ${item.entityType.dbValue}/${item.entityId}',
          );
        } catch (e) {
          await repo.markFailed(item.id, e);
          debugPrint(
            '[SyncQueue] FAIL ${item.operation.dbValue} ${item.entityType.dbValue}/${item.entityId}: $e',
          );
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
}
