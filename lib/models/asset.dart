import 'dart:math';
import 'package:flutter/material.dart';

enum AssetCategory {
  equipoDj,
  iluminacion,
  informatica,
  mobiliario,
  vehiculo,
  herramientas,
  otros;

  String get label {
    switch (this) {
      case AssetCategory.equipoDj:
        return 'Equipo DJ / Sonido';
      case AssetCategory.iluminacion:
        return 'Iluminación';
      case AssetCategory.informatica:
        return 'Informática';
      case AssetCategory.mobiliario:
        return 'Mobiliario';
      case AssetCategory.vehiculo:
        return 'Vehículo';
      case AssetCategory.herramientas:
        return 'Herramientas / Utillaje';
      case AssetCategory.otros:
        return 'Otros';
    }
  }

  String get dbValue => name;

  static AssetCategory fromDb(String value) {
    return AssetCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AssetCategory.otros,
    );
  }

  IconData get icono {
    switch (this) {
      case AssetCategory.equipoDj:
        return Icons.speaker;
      case AssetCategory.iluminacion:
        return Icons.lightbulb_outline;
      case AssetCategory.informatica:
        return Icons.laptop;
      case AssetCategory.mobiliario:
        return Icons.chair;
      case AssetCategory.vehiculo:
        return Icons.directions_car;
      case AssetCategory.herramientas:
        return Icons.handyman_outlined;
      case AssetCategory.otros:
        return Icons.inventory_2_outlined;
    }
  }

  /// Coeficiente máximo de amortización según tablas de Hacienda
  double get coeficienteMaxHacienda {
    switch (this) {
      case AssetCategory.equipoDj:
        return 0.20;
      case AssetCategory.iluminacion:
        return 0.20;
      case AssetCategory.informatica:
        return 0.25;
      case AssetCategory.mobiliario:
        return 0.10;
      case AssetCategory.vehiculo:
        return 0.16;
      case AssetCategory.herramientas:
        return 0.30;
      case AssetCategory.otros:
        return 0.10;
    }
  }

  /// Vida útil mínima en años según el coeficiente máximo
  int get vidaUtilSugerida {
    if (this == AssetCategory.vehiculo || this == AssetCategory.otros) {
      return 0;
    }
    return (1 / coeficienteMaxHacienda).round();
  }
}

class Asset {
  final int? id;
  final String? cloudId;
  final String? userId;
  final String descripcion;
  final DateTime fechaCompra;
  final double importeTotal;
  final double importeConIva;
  final double ivaRate;
  final double ivaAmount;
  final double valorResidual;
  final int vidaUtilAnos;
  final String metodoAmortizacion;
  final AssetCategory categoria;
  final String? documentoPath;
  final String? notas;
  final bool activo;
  final bool synced;
  final DateTime createdAt;
  final String? driveFileId;
  final String? driveFileUrl;
  final DateTime? driveSyncedAt;
  final String attachmentStatus;
  final String? attachmentError;
  final String? attachmentOriginalPath;
  final String? attachmentOriginalName;
  final String? attachmentStoredName;
  final String? attachmentMimeType;

  const Asset({
    this.id,
    this.cloudId,
    this.userId,
    required this.descripcion,
    required this.fechaCompra,
    required this.importeTotal,
    this.importeConIva = 0.0,
    this.ivaRate = 21.0,
    this.ivaAmount = 0.0,
    this.valorResidual = 0.0,
    required this.vidaUtilAnos,
    this.metodoAmortizacion = 'lineal',
    this.categoria = AssetCategory.otros,
    this.documentoPath,
    this.notas,
    this.activo = true,
    this.synced = false,
    required this.createdAt,
    this.driveFileId,
    this.driveFileUrl,
    this.driveSyncedAt,
    this.attachmentStatus = 'pending_upload',
    this.attachmentError,
    this.attachmentOriginalPath,
    this.attachmentOriginalName,
    this.attachmentStoredName,
    this.attachmentMimeType,
  });

  // ── Getters calculados ──────────────────────────────────────────────────────

  /// IVA deducible en el trimestre de compra (importe_con_iva - base imponible)
  double get ivaDeducible =>
      importeConIva > 0 ? importeConIva - importeTotal : 0.0;

  int get anosTranscurridos {
    final hoy = DateTime.now();
    int anos = hoy.year - fechaCompra.year;
    if (hoy.month < fechaCompra.month ||
        (hoy.month == fechaCompra.month && hoy.day < fechaCompra.day)) {
      anos--;
    }
    return max(0, anos);
  }

  int get mesesTranscurridos {
    final hoy = DateTime.now();
    int meses =
        (hoy.year - fechaCompra.year) * 12 + (hoy.month - fechaCompra.month);
    if (hoy.day < fechaCompra.day) meses--;
    return max(0, meses);
  }

  double get cuotaAnual => (importeTotal - valorResidual) / vidaUtilAnos;

  double get cuotaMensual => cuotaAnual / 12;

  double get cuotaTrimestral => cuotaAnual / 4;

  double get valorContable {
    final amortizado = cuotaAnual * anosTranscurridos;
    return max(valorResidual, importeTotal - amortizado);
  }

  bool get estaAmortizado => valorContable <= valorResidual;

  double get amortizacionAcumulada => importeTotal - valorContable;

  /// Cuota trimestral si el asset estaba activo en ese trimestre, 0.0 si no
  double cuotaTrimestreConcreto(int year, int quarter) {
    if (!activo) return 0.0;
    final inicioTrimestre = DateTime(year, (quarter - 1) * 3 + 1, 1);
    final finTrimestre = DateTime(year, quarter * 3 + 1, 0);
    // El asset debe haberse comprado antes del fin del trimestre
    if (fechaCompra.isAfter(finTrimestre)) return 0.0;
    // Ya estaba completamente amortizado al inicio del trimestre
    final anosAlInicio = max(0, inicioTrimestre.year - fechaCompra.year);
    final valorAlInicio = max(
      valorResidual,
      importeTotal - cuotaAnual * anosAlInicio,
    );
    if (valorAlInicio <= valorResidual) return 0.0;
    return cuotaTrimestral;
  }

  // ── Persistencia ────────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (cloudId != null) 'cloud_id': cloudId,
      'user_id': userId,
      'descripcion': descripcion,
      'fecha_compra': fechaCompra.toIso8601String(),
      'importe_total': importeTotal,
      'importe_con_iva': importeConIva,
      'iva_rate': ivaRate,
      'iva_amount': ivaAmount,
      'valor_residual': valorResidual,
      'vida_util_anos': vidaUtilAnos,
      'metodo_amortizacion': metodoAmortizacion,
      'categoria': categoria.dbValue,
      'documento_path': documentoPath,
      'notas': notas,
      'activo': activo ? 1 : 0,
      'synced': synced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'drive_file_id': driveFileId,
      'drive_file_url': driveFileUrl,
      'drive_synced_at': driveSyncedAt?.toIso8601String(),
      'attachment_status': attachmentStatus,
      'attachment_error': attachmentError,
      'attachment_original_path': attachmentOriginalPath,
      'attachment_original_name': attachmentOriginalName,
      'attachment_stored_name': attachmentStoredName,
      'attachment_mime_type': attachmentMimeType,
    };
  }

  factory Asset.fromMap(Map<String, dynamic> map) {
    return Asset(
      id: map['id'] as int?,
      cloudId: map['cloud_id'] as String?,
      userId: map['user_id'] as String?,
      descripcion: map['descripcion'] as String,
      fechaCompra: DateTime.parse(map['fecha_compra'] as String),
      importeTotal: (map['importe_total'] as num).toDouble(),
      importeConIva: (map['importe_con_iva'] as num? ?? 0).toDouble(),
      ivaRate: (map['iva_rate'] as num? ?? 21.0).toDouble(),
      ivaAmount: (map['iva_amount'] as num? ?? 0).toDouble(),
      valorResidual: (map['valor_residual'] as num? ?? 0).toDouble(),
      vidaUtilAnos: map['vida_util_anos'] as int,
      metodoAmortizacion: map['metodo_amortizacion'] as String? ?? 'lineal',
      categoria: AssetCategory.fromDb(map['categoria'] as String? ?? 'otros'),
      documentoPath: map['documento_path'] as String?,
      notas: map['notas'] as String?,
      activo: (map['activo'] as int? ?? 1) == 1,
      synced: (map['synced'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      driveFileId: map['drive_file_id'] as String?,
      driveFileUrl: map['drive_file_url'] as String?,
      driveSyncedAt: map['drive_synced_at'] != null
          ? DateTime.tryParse(map['drive_synced_at'] as String)
          : null,
      attachmentStatus:
          map['attachment_status'] as String? ?? 'pending_upload',
      attachmentError: map['attachment_error'] as String?,
      attachmentOriginalPath: map['attachment_original_path'] as String?,
      attachmentOriginalName: map['attachment_original_name'] as String?,
      attachmentStoredName: map['attachment_stored_name'] as String?,
      attachmentMimeType: map['attachment_mime_type'] as String?,
    );
  }

  Asset copyWith({
    int? id,
    String? cloudId,
    String? userId,
    String? descripcion,
    DateTime? fechaCompra,
    double? importeTotal,
    double? importeConIva,
    double? ivaRate,
    double? ivaAmount,
    double? valorResidual,
    int? vidaUtilAnos,
    String? metodoAmortizacion,
    AssetCategory? categoria,
    String? documentoPath,
    String? notas,
    bool? activo,
    bool? synced,
    DateTime? createdAt,
    String? driveFileId,
    String? driveFileUrl,
    DateTime? driveSyncedAt,
    String? attachmentStatus,
    String? attachmentError,
    String? attachmentOriginalPath,
    String? attachmentOriginalName,
    String? attachmentStoredName,
    String? attachmentMimeType,
    bool clearDriveFile = false,
  }) {
    return Asset(
      id: id ?? this.id,
      cloudId: cloudId ?? this.cloudId,
      userId: userId ?? this.userId,
      descripcion: descripcion ?? this.descripcion,
      fechaCompra: fechaCompra ?? this.fechaCompra,
      importeTotal: importeTotal ?? this.importeTotal,
      importeConIva: importeConIva ?? this.importeConIva,
      ivaRate: ivaRate ?? this.ivaRate,
      ivaAmount: ivaAmount ?? this.ivaAmount,
      valorResidual: valorResidual ?? this.valorResidual,
      vidaUtilAnos: vidaUtilAnos ?? this.vidaUtilAnos,
      metodoAmortizacion: metodoAmortizacion ?? this.metodoAmortizacion,
      categoria: categoria ?? this.categoria,
      documentoPath: documentoPath ?? this.documentoPath,
      notas: notas ?? this.notas,
      activo: activo ?? this.activo,
      synced: synced ?? this.synced,
      createdAt: createdAt ?? this.createdAt,
      driveFileId: clearDriveFile ? null : driveFileId ?? this.driveFileId,
      driveFileUrl: clearDriveFile ? null : driveFileUrl ?? this.driveFileUrl,
      driveSyncedAt: clearDriveFile
          ? null
          : driveSyncedAt ?? this.driveSyncedAt,
      attachmentStatus: attachmentStatus ?? this.attachmentStatus,
      attachmentError: attachmentError ?? this.attachmentError,
      attachmentOriginalPath:
          attachmentOriginalPath ?? this.attachmentOriginalPath,
      attachmentOriginalName:
          attachmentOriginalName ?? this.attachmentOriginalName,
      attachmentStoredName: attachmentStoredName ?? this.attachmentStoredName,
      attachmentMimeType: attachmentMimeType ?? this.attachmentMimeType,
    );
  }

  String? get attachmentDisplayName {
    final original = attachmentOriginalName?.trim();
    if (original != null && original.isNotEmpty) return original;
    final stored = attachmentStoredName?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final path = documentoPath?.trim();
    if (path == null || path.isEmpty) return null;
    return path.split('/').last;
  }
}
