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
    final maps = await db.query('clients', orderBy: 'nombre ASC');
    return maps.map((m) => Client.fromMap(m)).toList();
  }

  Future<Client?> getById(String id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('clients', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Client.fromMap(maps.first);
  }

  Future<List<Client>> search(String query) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'clients',
      where: 'nombre LIKE ? OR alias LIKE ? OR cif_nif LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'nombre ASC',
    );
    return maps.map((m) => Client.fromMap(m)).toList();
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
    await db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }
}
