import 'expense.dart';

class ExpenseExtractionResult {
  final String? concepto;
  final String? proveedor;
  final String? estacion;
  final String? numeroFactura;
  final DateTime? fecha;
  final DateTime? fechaOperacion;
  final double? importeBase;
  final double? importeIva;
  final double? ivaRate;
  final double? importeTotal;
  final double? descuento;
  final double? litros;
  final double? precioPorLitro;
  final String? matriculaVehiculo;
  final bool? esDeducible;
  final double? porcentajeDeduccion;
  final ExpenseCategory? categoria;
  final String? notas;
  final double confidence;
  final List<String> warnings;

  const ExpenseExtractionResult({
    this.concepto,
    this.proveedor,
    this.estacion,
    this.numeroFactura,
    this.fecha,
    this.fechaOperacion,
    this.importeBase,
    this.importeIva,
    this.ivaRate,
    this.importeTotal,
    this.descuento,
    this.litros,
    this.precioPorLitro,
    this.matriculaVehiculo,
    this.esDeducible,
    this.porcentajeDeduccion,
    this.categoria,
    this.notas,
    this.confidence = 0,
    this.warnings = const [],
  });

  factory ExpenseExtractionResult.fromMap(Map<String, dynamic> map) {
    return ExpenseExtractionResult(
      concepto: _readString(map['concepto']),
      proveedor: _readString(map['proveedor']),
      estacion: _readString(map['estacion']),
      numeroFactura: _readString(map['numero_factura']),
      fecha: _readDate(map['fecha']),
      fechaOperacion: _readDate(map['fecha_operacion']) ??
          _readDate(map['operation_date']),
      importeBase: _readDouble(map['importe_base']),
      importeIva: _readDouble(map['importe_iva']),
      ivaRate: _readDouble(map['iva_rate']),
      importeTotal: _readDouble(map['importe_total']),
      descuento: _readDouble(map['descuento']),
      litros: _readDouble(map['litros']),
      precioPorLitro: _readDouble(map['precio_por_litro']),
      matriculaVehiculo: _readString(map['matricula_vehiculo']),
      esDeducible: map['es_deducible'] as bool?,
      porcentajeDeduccion: _readDouble(map['porcentaje_deduccion']),
      categoria: _readCategory(map['categoria']),
      notas: _readString(map['notas']),
      confidence: _readDouble(map['confidence']) ?? 0,
      warnings: _readWarnings(map['warnings']),
    );
  }

  static String? _readString(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _readDate(dynamic value) {
    final raw = _readString(value);
    if (raw == null) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  static double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  static ExpenseCategory? _readCategory(dynamic value) {
    final raw = _readString(value)?.toLowerCase();
    if (raw == null) return null;
    for (final category in ExpenseCategory.values) {
      if (category.name == raw) return category;
    }
    return null;
  }

  static List<String> _readWarnings(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
}
