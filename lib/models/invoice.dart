import 'dart:convert';
import 'package:uuid/uuid.dart';

enum InvoiceStatus { borrador, enviada, pagada }

enum InvoiceType { normal, rectifying }

extension InvoiceTypeExtension on InvoiceType {
  String get label {
    switch (this) {
      case InvoiceType.normal:
        return 'Normal';
      case InvoiceType.rectifying:
        return 'Rectificativa';
    }
  }

  String get dbValue => name;

  static InvoiceType fromDb(String? value) {
    switch (value) {
      case 'rectifying':
        return InvoiceType.rectifying;
      case 'normal':
      default:
        return InvoiceType.normal;
    }
  }
}

enum RectificationType { substitution, difference }

extension RectificationTypeExtension on RectificationType {
  String get dbValue => name;

  static RectificationType? fromDb(String? value) {
    switch (value) {
      case 'substitution':
        return RectificationType.substitution;
      case 'difference':
        return RectificationType.difference;
      default:
        return null;
    }
  }
}

enum RectificationReasonType {
  amountCorrection,
  clientDataError,
  conceptError,
  discount,
  cancelledOperation,
  other,
}

extension RectificationReasonTypeExtension on RectificationReasonType {
  String get label {
    switch (this) {
      case RectificationReasonType.amountCorrection:
        return 'Corrección de importe';
      case RectificationReasonType.clientDataError:
        return 'Error en datos del cliente';
      case RectificationReasonType.conceptError:
        return 'Error en concepto facturado';
      case RectificationReasonType.discount:
        return 'Aplicación de descuento';
      case RectificationReasonType.cancelledOperation:
        return 'Operación anulada';
      case RectificationReasonType.other:
        return 'Otro';
    }
  }

  String get dbValue => name;

  static RectificationReasonType? fromDb(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    switch (value) {
      case 'amountCorrection':
        return RectificationReasonType.amountCorrection;
      case 'clientDataError':
        return RectificationReasonType.clientDataError;
      case 'conceptError':
        return RectificationReasonType.conceptError;
      case 'discount':
        return RectificationReasonType.discount;
      case 'cancelledOperation':
        return RectificationReasonType.cancelledOperation;
      case 'other':
      default:
        return RectificationReasonType.other;
    }
  }
}

extension InvoiceStatusExtension on InvoiceStatus {
  String get label {
    switch (this) {
      case InvoiceStatus.borrador:
        return 'Borrador';
      case InvoiceStatus.enviada:
        return 'Pendiente de cobro';
      case InvoiceStatus.pagada:
        return 'Cobrada';
    }
  }

  String get dbValue => name;

  static InvoiceStatus fromDb(String value) {
    switch (value) {
      case 'borrador':
        return InvoiceStatus.borrador;
      case 'enviada':
        return InvoiceStatus.enviada;
      case 'pagada':
        return InvoiceStatus.pagada;
      default:
        return InvoiceStatus.borrador;
    }
  }
}

class InvoiceLineItem {
  final int cantidad;
  final String descripcion;
  final double precioUnitario;
  final double totalLinea;

  InvoiceLineItem({
    required this.cantidad,
    required this.descripcion,
    required this.precioUnitario,
    double? totalLinea,
  }) : totalLinea = totalLinea ?? (cantidad * precioUnitario);

  Map<String, dynamic> toMap() {
    return {
      'cantidad': cantidad,
      'descripcion': descripcion,
      'precio_unitario': precioUnitario,
      'total_linea': totalLinea,
    };
  }

  factory InvoiceLineItem.fromMap(Map<String, dynamic> map) {
    return InvoiceLineItem(
      cantidad: map['cantidad'] as int,
      descripcion: map['descripcion'] as String,
      precioUnitario: (map['precio_unitario'] as num).toDouble(),
      totalLinea: (map['total_linea'] as num).toDouble(),
    );
  }
}

class Invoice {
  final String id;
  final int numero;
  final DateTime fecha;
  final String clientId;
  final String gigId;
  final List<InvoiceLineItem> items;
  final double subtotal;
  final double ivaRate;
  final double ivaAmount;
  final double irpfRate;
  final double irpfAmount;
  final double total;
  final InvoiceStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? driveFileId;
  final String? driveFileUrl;
  final DateTime? driveSyncedAt;
  final DateTime? driveUploadedAt;
  final String driveSyncStatus;
  final bool isFiscallyIssued;
  final String? fiscalHash;
  final String? fiscalRecordId;
  final InvoiceType invoiceType;
  final String? rectifiesInvoiceId;
  final String? rectificationReason;
  final RectificationReasonType? rectificationReasonType;
  final String? rectificationReasonDescription;
  final RectificationType? rectificationType;
  final String? originalInvoiceNumber;
  final DateTime? originalInvoiceDate;

  Invoice({
    String? id,
    required this.numero,
    required this.fecha,
    required this.clientId,
    required this.gigId,
    required this.items,
    required this.subtotal,
    this.ivaRate = 0.21,
    double? ivaAmount,
    this.irpfRate = 0.0,
    double? irpfAmount,
    double? total,
    this.status = InvoiceStatus.borrador,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.driveFileId,
    this.driveFileUrl,
    this.driveSyncedAt,
    this.driveUploadedAt,
    this.driveSyncStatus = 'pending',
    this.isFiscallyIssued = false,
    this.fiscalHash,
    this.fiscalRecordId,
    this.invoiceType = InvoiceType.normal,
    this.rectifiesInvoiceId,
    this.rectificationReason,
    this.rectificationReasonType,
    this.rectificationReasonDescription,
    this.rectificationType,
    this.originalInvoiceNumber,
    this.originalInvoiceDate,
  }) : id = id ?? const Uuid().v4(),
       ivaAmount = ivaAmount ?? (subtotal * ivaRate),
       irpfAmount = irpfAmount ?? (subtotal * irpfRate),
       total =
           total ??
           (subtotal +
               (ivaAmount ?? subtotal * ivaRate) -
               (irpfAmount ?? subtotal * irpfRate)),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Invoice copyWith({
    int? numero,
    DateTime? fecha,
    String? clientId,
    String? gigId,
    List<InvoiceLineItem>? items,
    double? subtotal,
    double? ivaRate,
    double? ivaAmount,
    double? irpfRate,
    double? irpfAmount,
    double? total,
    InvoiceStatus? status,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? driveFileId,
    String? driveFileUrl,
    DateTime? driveSyncedAt,
    DateTime? driveUploadedAt,
    String? driveSyncStatus,
    bool? isFiscallyIssued,
    String? fiscalHash,
    String? fiscalRecordId,
    InvoiceType? invoiceType,
    String? rectifiesInvoiceId,
    String? rectificationReason,
    RectificationReasonType? rectificationReasonType,
    String? rectificationReasonDescription,
    RectificationType? rectificationType,
    String? originalInvoiceNumber,
    DateTime? originalInvoiceDate,
    bool clearDriveFile = false,
    bool clearFiscalRecord = false,
  }) {
    return Invoice(
      id: id,
      numero: numero ?? this.numero,
      fecha: fecha ?? this.fecha,
      clientId: clientId ?? this.clientId,
      gigId: gigId ?? this.gigId,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      ivaRate: ivaRate ?? this.ivaRate,
      ivaAmount: ivaAmount ?? this.ivaAmount,
      irpfRate: irpfRate ?? this.irpfRate,
      irpfAmount: irpfAmount ?? this.irpfAmount,
      total: total ?? this.total,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      driveFileId: clearDriveFile ? null : driveFileId ?? this.driveFileId,
      driveFileUrl: clearDriveFile ? null : driveFileUrl ?? this.driveFileUrl,
      driveSyncedAt: clearDriveFile
          ? null
          : driveSyncedAt ?? this.driveSyncedAt,
      driveUploadedAt: clearDriveFile
          ? null
          : driveUploadedAt ?? this.driveUploadedAt,
      driveSyncStatus: clearDriveFile
          ? 'pending'
          : driveSyncStatus ?? this.driveSyncStatus,
      isFiscallyIssued: isFiscallyIssued ?? this.isFiscallyIssued,
      fiscalHash: clearFiscalRecord ? null : fiscalHash ?? this.fiscalHash,
      fiscalRecordId: clearFiscalRecord
          ? null
          : fiscalRecordId ?? this.fiscalRecordId,
      invoiceType: invoiceType ?? this.invoiceType,
      rectifiesInvoiceId: rectifiesInvoiceId ?? this.rectifiesInvoiceId,
      rectificationReason: rectificationReason ?? this.rectificationReason,
      rectificationReasonType:
          rectificationReasonType ?? this.rectificationReasonType,
      rectificationReasonDescription:
          rectificationReasonDescription ?? this.rectificationReasonDescription,
      rectificationType: rectificationType ?? this.rectificationType,
      originalInvoiceNumber:
          originalInvoiceNumber ?? this.originalInvoiceNumber,
      originalInvoiceDate: originalInvoiceDate ?? this.originalInvoiceDate,
    );
  }

  Invoice touch() => copyWith(updatedAt: DateTime.now());
  bool get isRectifying => invoiceType == InvoiceType.rectifying;
  bool get isFiscallyLocked =>
      isFiscallyIssued || (fiscalHash?.trim().isNotEmpty ?? false);
  String get visualSeries => isRectifying ? 'R' : 'F';
  String get visualNumber =>
      '$visualSeries-${fecha.year}-${numero.toString().padLeft(4, '0')}';
  String get displayName => isRectifying ? 'Factura rectificativa' : 'Factura';
  String get fiscalStateLabel => isFiscallyIssued ? 'Emitida' : 'Pendiente';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'numero': numero,
      'fecha': fecha.toIso8601String(),
      'client_id': clientId,
      'gig_id': gigId,
      'items': jsonEncode(items.map((e) => e.toMap()).toList()),
      'subtotal': subtotal,
      'iva_rate': ivaRate,
      'iva_amount': ivaAmount,
      'irpf_rate': irpfRate,
      'irpf_amount': irpfAmount,
      'total': total,
      'status': status.dbValue,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
      'drive_file_id': driveFileId,
      'drive_file_url': driveFileUrl,
      'drive_synced_at': driveSyncedAt?.toIso8601String(),
      'drive_uploaded_at': driveUploadedAt?.toIso8601String(),
      'drive_sync_status': driveSyncStatus,
      'is_fiscally_issued': isFiscallyIssued ? 1 : 0,
      'fiscal_hash': fiscalHash,
      'fiscal_record_id': fiscalRecordId,
      'invoice_type': invoiceType.dbValue,
      'rectifies_invoice_id': rectifiesInvoiceId,
      'rectification_reason': rectificationReason,
      'rectification_reason_type': rectificationReasonType?.dbValue,
      'rectification_reason_description': rectificationReasonDescription,
      'rectification_type': rectificationType?.dbValue,
      'original_invoice_number': originalInvoiceNumber,
      'original_invoice_date': originalInvoiceDate?.toIso8601String(),
    };
  }

  factory Invoice.fromMap(Map<String, dynamic> map) {
    final itemsList = jsonDecode(map['items'] as String) as List;
    return Invoice(
      id: map['id'] as String,
      numero: map['numero'] as int,
      fecha: DateTime.parse(map['fecha'] as String),
      clientId: map['client_id'] as String,
      gigId: map['gig_id'] as String,
      items: itemsList
          .map((e) => InvoiceLineItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      subtotal: (map['subtotal'] as num).toDouble(),
      ivaRate: (map['iva_rate'] as num).toDouble(),
      ivaAmount: (map['iva_amount'] as num).toDouble(),
      irpfRate: (map['irpf_rate'] as num?)?.toDouble() ?? 0.0,
      irpfAmount: (map['irpf_amount'] as num?)?.toDouble() ?? 0.0,
      total: (map['total'] as num).toDouble(),
      status: InvoiceStatusExtension.fromDb(map['status'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(
        (map['updated_at'] ?? map['created_at']) as String,
      ),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
      driveFileId: map['drive_file_id'] as String?,
      driveFileUrl: map['drive_file_url'] as String?,
      driveSyncedAt: map['drive_synced_at'] != null
          ? DateTime.tryParse(map['drive_synced_at'] as String)
          : null,
      driveUploadedAt: map['drive_uploaded_at'] != null
          ? DateTime.tryParse(map['drive_uploaded_at'] as String)
          : null,
      driveSyncStatus:
          (map['drive_sync_status'] as String?)?.trim().isNotEmpty == true
          ? (map['drive_sync_status'] as String)
          : 'pending',
      isFiscallyIssued: (map['is_fiscally_issued'] is bool)
          ? map['is_fiscally_issued'] as bool
          : (map['is_fiscally_issued'] as int? ?? 0) == 1,
      fiscalHash: map['fiscal_hash'] as String?,
      fiscalRecordId: map['fiscal_record_id'] as String?,
      invoiceType: InvoiceTypeExtension.fromDb(map['invoice_type'] as String?),
      rectifiesInvoiceId: map['rectifies_invoice_id'] as String?,
      rectificationReason: map['rectification_reason'] as String?,
      rectificationReasonType: RectificationReasonTypeExtension.fromDb(
        map['rectification_reason_type'] as String?,
      ),
      rectificationReasonDescription:
          map['rectification_reason_description'] as String? ??
          map['rectification_reason'] as String?,
      rectificationType: RectificationTypeExtension.fromDb(
        map['rectification_type'] as String?,
      ),
      originalInvoiceNumber: map['original_invoice_number'] as String?,
      originalInvoiceDate: map['original_invoice_date'] != null
          ? DateTime.tryParse(map['original_invoice_date'] as String)
          : null,
    );
  }
}
