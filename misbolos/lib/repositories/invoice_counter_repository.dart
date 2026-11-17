import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/invoice_counter.dart';

/// Los números de siguiente factura fijados a mano, en este dispositivo.
class InvoiceCounterRepository {
  InvoiceCounterRepository._();
  static final InvoiceCounterRepository instance = InvoiceCounterRepository._();

  static const String tabla = 'invoice_counters';

  Future<InvoiceCounter?> get({
    required String serie,
    required int fiscalYear,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final filas = await db.query(
      tabla,
      where: 'serie = ? AND fiscal_year = ?',
      whereArgs: [serie, fiscalYear],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return InvoiceCounter.fromMap(filas.first);
  }

  Future<List<InvoiceCounter>> getAll() async {
    final db = await DatabaseHelper.instance.database;
    final filas = await db.query(tabla);
    return filas.map(InvoiceCounter.fromMap).toList();
  }

  /// Guarda el contador tal cual, sin más comprobaciones.
  ///
  /// Quien lo llama ya ha validado el número: la pantalla con
  /// [sePuedeFijarNumero], y la sincronización porque viene de la nube.
  Future<void> guardar(InvoiceCounter contador) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      tabla,
      contador.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Aplica lo que viene de la nube, respetando quién cambió el último.
  ///
  /// Devuelve el contador que queda, que puede ser el que ya había.
  Future<InvoiceCounter?> fusionarDesdeNube(InvoiceCounter nube) async {
    final local = await get(serie: nube.serie, fiscalYear: nube.fiscalYear);
    final ganador = fusionarContadores(local, nube);
    if (ganador == null) return null;
    if (local == null || !ganador.updatedAt.isAtSameMomentAs(local.updatedAt)) {
      await guardar(ganador);
    }
    return ganador;
  }
}
