import 'package:sqflite/sqflite.dart';
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

  Future<void> updateDriveMetadata({
    required int id,
    required String driveFileId,
    required String? driveFileUrl,
    required DateTime driveSyncedAt,
  }) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'assets',
      {
        'drive_file_id': driveFileId,
        'drive_file_url': driveFileUrl,
        'drive_synced_at': driveSyncedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearDriveMetadata(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'assets',
      {
        'drive_file_id': null,
        'drive_file_url': null,
        'drive_synced_at': null,
      },
      where: 'id = ?',
      whereArgs: [id],
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

  /// Guarda el cloud_id generado al subir por primera vez
  Future<void> saveCloudId(int localId, String cloudId) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'assets',
      {'cloud_id': cloudId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Upsert por cloud_id (para sincronización descendente)
  Future<void> upsertByCloudId(Asset asset) async {
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'assets',
      where: 'cloud_id = ?',
      whereArgs: [asset.cloudId],
    );
    if (existing.isEmpty) {
      await db.insert(
        'assets',
        asset.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      final localId = existing.first['id'] as int;
      final localAsset = Asset.fromMap(existing.first);
      final merged = asset.copyWith(
        id: localId,
        documentoPath: (asset.documentoPath?.trim().isNotEmpty ?? false)
            ? asset.documentoPath
            : localAsset.documentoPath,
        driveFileId: (asset.driveFileId?.trim().isNotEmpty ?? false)
            ? asset.driveFileId
            : localAsset.driveFileId,
        driveFileUrl: (asset.driveFileUrl?.trim().isNotEmpty ?? false)
            ? asset.driveFileUrl
            : localAsset.driveFileUrl,
        driveSyncedAt: asset.driveSyncedAt ?? localAsset.driveSyncedAt,
        attachmentStatus: (asset.attachmentStatus.trim().isNotEmpty)
            ? asset.attachmentStatus
            : localAsset.attachmentStatus,
        attachmentError: asset.attachmentError ?? localAsset.attachmentError,
        attachmentOriginalPath:
            (asset.attachmentOriginalPath?.trim().isNotEmpty ?? false)
            ? asset.attachmentOriginalPath
            : localAsset.attachmentOriginalPath,
        attachmentOriginalName:
            (asset.attachmentOriginalName?.trim().isNotEmpty ?? false)
            ? asset.attachmentOriginalName
            : localAsset.attachmentOriginalName,
        attachmentStoredName:
            (asset.attachmentStoredName?.trim().isNotEmpty ?? false)
            ? asset.attachmentStoredName
            : localAsset.attachmentStoredName,
        attachmentMimeType: (asset.attachmentMimeType?.trim().isNotEmpty ?? false)
            ? asset.attachmentMimeType
            : localAsset.attachmentMimeType,
      );
      await db.update(
        'assets',
        merged.toMap(),
        where: 'id = ?',
        whereArgs: [localId],
      );
    }
  }

  /// Borra por cloud_id (para sincronización descendente)
  Future<void> deleteByCloudId(String cloudId) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('assets', where: 'cloud_id = ?', whereArgs: [cloudId]);
  }
}
