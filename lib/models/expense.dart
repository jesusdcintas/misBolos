enum ExpenseCategory {
  combustible,
  transporte,
  equipo,
  software,
  dietas,
  publicidad,
  formacion,
  otros,
}

extension ExpenseCategoryExtension on ExpenseCategory {
  String get label {
    switch (this) {
      case ExpenseCategory.combustible:
        return 'Combustible';
      case ExpenseCategory.transporte:
        return 'Transporte';
      case ExpenseCategory.equipo:
        return 'Equipo';
      case ExpenseCategory.software:
        return 'Software';
      case ExpenseCategory.dietas:
        return 'Dietas';
      case ExpenseCategory.publicidad:
        return 'Publicidad';
      case ExpenseCategory.formacion:
        return 'Formación';
      case ExpenseCategory.otros:
        return 'Otros';
    }
  }

  String get dbValue => name;

  static ExpenseCategory fromDb(String value) {
    return ExpenseCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ExpenseCategory.otros,
    );
  }
}

class Expense {
  final int? id;
  final String? cloudId;
  final String? userId;
  final DateTime fecha;
  final String concepto;
  final String? proveedor;
  final double importeBase;
  final double ivaRate;
  final double ivaAmount;
  final double total;
  final ExpenseCategory categoria;
  final bool esDeducible;
  final double porcentajeDeduccion;
  final String? documentoPath;
  final String? notas;
  final bool synced;
  final DateTime createdAt;
  final String? driveFileId;
  final String? driveFileUrl;
  final DateTime? driveSyncedAt;

  Expense({
    this.id,
    this.cloudId,
    this.userId,
    required this.fecha,
    required this.concepto,
    this.proveedor,
    required this.importeBase,
    this.ivaRate = 21.0,
    required this.ivaAmount,
    required this.total,
    this.categoria = ExpenseCategory.otros,
    this.esDeducible = true,
    this.porcentajeDeduccion = 100.0,
    this.documentoPath,
    this.notas,
    this.synced = false,
    DateTime? createdAt,
    this.driveFileId,
    this.driveFileUrl,
    this.driveSyncedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get importeDeducible => importeBase * (porcentajeDeduccion / 100);

  Expense copyWith({
    int? id,
    String? cloudId,
    String? userId,
    DateTime? fecha,
    String? concepto,
    String? proveedor,
    double? importeBase,
    double? ivaRate,
    double? ivaAmount,
    double? total,
    ExpenseCategory? categoria,
    bool? esDeducible,
    double? porcentajeDeduccion,
    String? documentoPath,
    String? notas,
    bool? synced,
    DateTime? createdAt,
    String? driveFileId,
    String? driveFileUrl,
    DateTime? driveSyncedAt,
    bool clearDriveFile = false,
  }) {
    return Expense(
      id: id ?? this.id,
      cloudId: cloudId ?? this.cloudId,
      userId: userId ?? this.userId,
      fecha: fecha ?? this.fecha,
      concepto: concepto ?? this.concepto,
      proveedor: proveedor ?? this.proveedor,
      importeBase: importeBase ?? this.importeBase,
      ivaRate: ivaRate ?? this.ivaRate,
      ivaAmount: ivaAmount ?? this.ivaAmount,
      total: total ?? this.total,
      categoria: categoria ?? this.categoria,
      esDeducible: esDeducible ?? this.esDeducible,
      porcentajeDeduccion: porcentajeDeduccion ?? this.porcentajeDeduccion,
      documentoPath: documentoPath ?? this.documentoPath,
      notas: notas ?? this.notas,
      synced: synced ?? this.synced,
      createdAt: createdAt ?? this.createdAt,
      driveFileId: clearDriveFile ? null : driveFileId ?? this.driveFileId,
      driveFileUrl: clearDriveFile ? null : driveFileUrl ?? this.driveFileUrl,
      driveSyncedAt: clearDriveFile
          ? null
          : driveSyncedAt ?? this.driveSyncedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (cloudId != null) 'cloud_id': cloudId,
      'user_id': userId,
      'fecha': fecha.toIso8601String(),
      'concepto': concepto,
      'proveedor': proveedor,
      'importe_base': importeBase,
      'iva_rate': ivaRate,
      'iva_amount': ivaAmount,
      'total': total,
      'categoria': categoria.dbValue,
      'es_deducible': esDeducible ? 1 : 0,
      'porcentaje_deduccion': porcentajeDeduccion,
      'documento_path': documentoPath,
      'notas': notas,
      'synced': synced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'drive_file_id': driveFileId,
      'drive_file_url': driveFileUrl,
      'drive_synced_at': driveSyncedAt?.toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      cloudId: map['cloud_id'] as String?,
      userId: map['user_id'] as String?,
      fecha: DateTime.parse(map['fecha'] as String),
      concepto: map['concepto'] as String,
      proveedor: map['proveedor'] as String?,
      importeBase: (map['importe_base'] as num).toDouble(),
      ivaRate: (map['iva_rate'] as num).toDouble(),
      ivaAmount: (map['iva_amount'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
      categoria: ExpenseCategoryExtension.fromDb(map['categoria'] as String),
      esDeducible: (map['es_deducible'] as int) == 1,
      porcentajeDeduccion: (map['porcentaje_deduccion'] as num).toDouble(),
      documentoPath: map['documento_path'] as String?,
      notas: map['notas'] as String?,
      synced: (map['synced'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      driveFileId: map['drive_file_id'] as String?,
      driveFileUrl: map['drive_file_url'] as String?,
      driveSyncedAt: map['drive_synced_at'] != null
          ? DateTime.tryParse(map['drive_synced_at'] as String)
          : null,
    );
  }
}
