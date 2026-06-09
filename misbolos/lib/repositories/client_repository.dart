import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/client.dart';

class ClientRepository {
  static final ClientRepository instance = ClientRepository._();
  ClientRepository._();

  Future<void> upsert(Client client) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'clients',
      client.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Client>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'clients',
      where: 'deleted_at IS NULL',
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => Client.fromMap(m)).toList();
  }

  Future<Client?> getById(String id, {bool includeDeleted = false}) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'clients',
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Client.fromMap(maps.first);
  }

  Future<List<Client>> search(String query) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'clients',
      where:
          'deleted_at IS NULL AND (nombre LIKE ? OR alias LIKE ? OR aliases LIKE ? OR cif_nif LIKE ?)',
      whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%'],
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => Client.fromMap(m)).toList();
  }

  Future<Client?> findByNameOrAlias(String name) async {
    final db = await DatabaseHelper.instance.database;
    final normalized = name.toLowerCase().trim();

    // Search by nombre exact match (case-insensitive)
    var maps = await db.query(
      'clients',
      where: 'deleted_at IS NULL AND LOWER(nombre) = ?',
      whereArgs: [normalized],
    );
    if (maps.isNotEmpty) return Client.fromMap(maps.first);

    // Search by alias exact match
    maps = await db.query(
      'clients',
      where: 'deleted_at IS NULL AND LOWER(alias) = ?',
      whereArgs: [normalized],
    );
    if (maps.isNotEmpty) return Client.fromMap(maps.first);

    // Search in aliases JSON array
    maps = await db.query(
      'clients',
      where: 'deleted_at IS NULL AND LOWER(aliases) LIKE ?',
      whereArgs: ['%"$normalized"%'],
    );
    if (maps.isNotEmpty) {
      // Verify: check actual parsed aliases for exact match
      for (final m in maps) {
        final client = Client.fromMap(m);
        if (client.aliases.any((a) => a.toLowerCase() == normalized)) {
          return client;
        }
      }
    }
    return null;
  }

  Future<void> insert(Client client) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('clients', client.toMap());
  }

  Future<void> update(Client client) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'clients',
      client.toMap(),
      where: 'id = ?',
      whereArgs: [client.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'clients',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
