import 'package:uuid/uuid.dart';

enum GigStatus {
  pendiente,
  facturaGenerada,
  facturaEnviada,
  pagado,
  cancelado,
  cobradoEnB,
}

extension GigStatusExtension on GigStatus {
  String get label {
    switch (this) {
      case GigStatus.pendiente:
        return 'Pendiente';
      case GigStatus.facturaGenerada:
        return 'Factura generada';
      case GigStatus.facturaEnviada:
        return 'Factura enviada';
      case GigStatus.pagado:
        return 'Pagado';
      case GigStatus.cancelado:
        return 'Cancelado';
      case GigStatus.cobradoEnB:
        return 'Cobrado en B';
    }
  }

  String get dbValue {
    switch (this) {
      case GigStatus.pendiente:
        return 'pendiente';
      case GigStatus.facturaGenerada:
        return 'factura_generada';
      case GigStatus.facturaEnviada:
        return 'factura_enviada';
      case GigStatus.pagado:
        return 'pagado';
      case GigStatus.cancelado:
        return 'cancelado';
      case GigStatus.cobradoEnB:
        return 'cobrado_en_b';
    }
  }

  static GigStatus fromDb(String value) {
    switch (value) {
      case 'pendiente':
        return GigStatus.pendiente;
      case 'factura_generada':
        return GigStatus.facturaGenerada;
      case 'factura_enviada':
        return GigStatus.facturaEnviada;
      case 'pagado':
        return GigStatus.pagado;
      case 'cancelado':
        return GigStatus.cancelado;
      case 'cobrado_en_b':
        return GigStatus.cobradoEnB;
      default:
        return GigStatus.pendiente;
    }
  }
}

class Gig {
  final String id;
  final DateTime fecha;
  final String clientId;
  final String? notas;
  final double? cachet;
  final bool facturable;
  final GigStatus status;
  final String? invoiceId;
  final DateTime createdAt;

  Gig({
    String? id,
    required this.fecha,
    required this.clientId,
    this.notas,
    this.cachet,
    this.facturable = true,
    this.status = GigStatus.pendiente,
    this.invoiceId,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Gig copyWith({
    DateTime? fecha,
    String? clientId,
    String? notas,
    double? cachet,
    bool? facturable,
    GigStatus? status,
    String? invoiceId,
  }) {
    return Gig(
      id: id,
      fecha: fecha ?? this.fecha,
      clientId: clientId ?? this.clientId,
      notas: notas ?? this.notas,
      cachet: cachet ?? this.cachet,
      facturable: facturable ?? this.facturable,
      status: status ?? this.status,
      invoiceId: invoiceId ?? this.invoiceId,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fecha': fecha.toIso8601String(),
      'client_id': clientId,
      'notas': notas,
      'cachet': cachet,
      'facturable': facturable ? 1 : 0,
      'status': status.dbValue,
      'invoice_id': invoiceId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Gig.fromMap(Map<String, dynamic> map) {
    return Gig(
      id: map['id'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      clientId: map['client_id'] as String,
      notas: map['notas'] as String?,
      cachet: map['cachet'] != null ? (map['cachet'] as num).toDouble() : null,
      facturable: (map['facturable'] as int) == 1,
      status: GigStatusExtension.fromDb(map['status'] as String),
      invoiceId: map['invoice_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
