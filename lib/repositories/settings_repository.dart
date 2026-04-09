import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  Future<AppSettings> get() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('app_settings', where: 'id = 1');
    if (maps.isEmpty) return AppSettings();
    return AppSettings.fromMap(maps.first);
  }

  Future<void> save(AppSettings settings) async {
    final db = await DatabaseHelper.instance.database;
    final map = settings.toMap();
    map['id'] = 1;
    await db.insert(
      'app_settings',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateField(String key, dynamic value) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'app_settings',
      {key: value},
      where: 'id = 1',
    );
  }
}
