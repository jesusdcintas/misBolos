import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/expense.dart';

class ExpenseRepository {
  static final ExpenseRepository instance = ExpenseRepository._();
  ExpenseRepository._();

  Future<List<Expense>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('expenses', orderBy: 'fecha DESC');
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<List<Expense>> getByDateRange(DateTime from, DateTime to) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'expenses',
      where: 'fecha >= ? AND fecha <= ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'fecha DESC',
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<List<Expense>> getByCategoria(ExpenseCategory categoria) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'expenses',
      where: 'categoria = ?',
      whereArgs: [categoria.dbValue],
      orderBy: 'fecha DESC',
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  Future<Expense?> getById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('expenses', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Expense.fromMap(maps.first);
  }

  Future<int> insert(Expense expense) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert(
      'expenses',
      expense.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(Expense expense) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'expenses',
      expense.toMap(),
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, double>> getTotalesPorCategoria(
      int year, int quarter) async {
    final range = _quarterRange(year, quarter);
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'expenses',
      where: 'fecha >= ? AND fecha <= ?',
      whereArgs: [range.$1.toIso8601String(), range.$2.toIso8601String()],
    );
    final totales = <String, double>{};
    for (final m in maps) {
      final cat = m['categoria'] as String;
      final total = (m['total'] as num).toDouble();
      totales[cat] = (totales[cat] ?? 0.0) + total;
    }
    return totales;
  }

  Future<double> getTotalDeducibleTrimestre(int year, int quarter) async {
    final range = _quarterRange(year, quarter);
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'expenses',
      where: 'fecha >= ? AND fecha <= ? AND es_deducible = 1',
      whereArgs: [range.$1.toIso8601String(), range.$2.toIso8601String()],
    );
    return maps.fold<double>(0.0, (sum, m) {
      final base = (m['importe_base'] as num).toDouble();
      final pct = (m['porcentaje_deduccion'] as num).toDouble();
      return sum + base * (pct / 100);
    });
  }

  Future<double> getTotalIvaSoportadoTrimestre(int year, int quarter) async {
    final range = _quarterRange(year, quarter);
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'expenses',
      where: 'fecha >= ? AND fecha <= ? AND es_deducible = 1',
      whereArgs: [range.$1.toIso8601String(), range.$2.toIso8601String()],
    );
    return maps.fold<double>(0.0, (sum, m) {
      final iva = (m['iva_amount'] as num).toDouble();
      final pct = (m['porcentaje_deduccion'] as num).toDouble();
      return sum + iva * (pct / 100);
    });
  }

  (DateTime, DateTime) _quarterRange(int year, int quarter) {
    final startMonth = (quarter - 1) * 3 + 1;
    final from = DateTime(year, startMonth, 1);
    final to = DateTime(year, startMonth + 3, 0, 23, 59, 59);
    return (from, to);
  }

  /// Guarda el cloud_id generado al subir por primera vez
  Future<void> saveCloudId(int localId, String cloudId) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'expenses',
      {'cloud_id': cloudId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Upsert por cloud_id (para sincronización descendente)
  Future<void> upsertByCloudId(Expense expense) async {
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'expenses',
      where: 'cloud_id = ?',
      whereArgs: [expense.cloudId],
    );
    if (existing.isEmpty) {
      await db.insert('expenses', expense.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      final localId = existing.first['id'] as int;
      await db.update(
        'expenses',
        expense.copyWith(id: localId).toMap(),
        where: 'id = ?',
        whereArgs: [localId],
      );
    }
  }

  /// Borra por cloud_id (para sincronización descendente)
  Future<void> deleteByCloudId(String cloudId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('expenses', where: 'cloud_id = ?', whereArgs: [cloudId]);
  }
}
