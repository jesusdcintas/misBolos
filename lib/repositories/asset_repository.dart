import '../database/database_helper.dart';
import '../models/asset.dart';

class AssetRepository {
  static final AssetRepository instance = AssetRepository._();
  AssetRepository._();

  Future<List<Asset>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('assets', orderBy: 'fecha_compra DESC');
    return maps.map(Asset.fromMap).toList();
  }

  Future<List<Asset>> getActivos() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query(
      'assets',
      where: 'activo = 1',
      orderBy: 'fecha_compra DESC',
    );
    return maps.map(Asset.fromMap).toList();
  }

  Future<Asset?> getById(int id) async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query('assets', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Asset.fromMap(maps.first);
  }

  Future<int> insert(Asset asset) async {
    final db = await DatabaseHelper.instance.database;
    return db.insert('assets', asset.toMap());
  }

  Future<void> update(Asset asset) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'assets',
      asset.toMap(),
      where: 'id = ?',
      whereArgs: [asset.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('assets', where: 'id = ?', whereArgs: [id]);
  }

  /// Suma cuotaTrimestreConcreto de todos los assets activos en ese trimestre
  Future<double> getTotalAmortizacionTrimestre(int year, int quarter) async {
    final activos = await getActivos();
    return activos.fold<double>(
      0.0,
      (sum, a) => sum + a.cuotaTrimestreConcreto(year, quarter),
    );
  }

  /// Assets cuya amortización termina en los próximos N meses
  Future<List<Asset>> getProximosAmortizar(int meses) async {
    final activos = await getActivos();
    final limite = DateTime.now().add(Duration(days: meses * 30));
    return activos.where((a) {
      if (a.estaAmortizado) return false;
      final fechaFin = DateTime(
        a.fechaCompra.year + a.vidaUtilAnos,
        a.fechaCompra.month,
        a.fechaCompra.day,
      );
      return fechaFin.isBefore(limite);
    }).toList();
  }
}
