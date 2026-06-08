import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/sync_queue_item.dart';

class SyncQueueRepository {
  static final SyncQueueRepository instance = SyncQueueRepository._();
  SyncQueueRepository._();

  Future<void> enqueue({
    required SyncEntityType entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final item = SyncQueueItem(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
    );
    await db.insert(
      'sync_queue',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SyncQueueItem>> pending({int maxAttempts = 8}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sync_queue',
      where: 'attempts < ?',
      whereArgs: [maxAttempts],
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  Future<bool> hasPending(String entityType, String entityId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'sync_queue',
      columns: ['id'],
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> remove(String id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailed(String id, Object error) async {
    final db = await DatabaseHelper.instance.database;
    await db.rawUpdate(
      '''
      UPDATE sync_queue
      SET attempts = attempts + 1,
          last_error = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [error.toString(), DateTime.now().toIso8601String(), id],
    );
  }

  Future<int> countPending({int maxAttempts = 8}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM sync_queue
      WHERE attempts < ?
      ''',
      [maxAttempts],
    );
    final raw = rows.first['total'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }
}
