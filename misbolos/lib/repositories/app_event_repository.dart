import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/app_event.dart';

class AppEventRepository {
  static final AppEventRepository instance = AppEventRepository._();
  AppEventRepository._();

  Future<void> insert(AppEvent event) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'app_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AppEvent>> getByEntity(String entityType, String entityId) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'app_events',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return maps.map(AppEvent.fromMap).toList();
  }

  Future<List<AppEvent>> getRecent({int limit = 100}) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'app_events',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(AppEvent.fromMap).toList();
  }
}
