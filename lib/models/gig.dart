import 'package:uuid/uuid.dart';

enum GigStatus {
  confirmado,
  facturado,
  cobrado,
  confirmadoB,
  realizadoB,
  cobradoB,
  cancelado,
}

extension GigStatusExtension on GigStatus {
  String get label {
      switch (this) {
      case GigStatus.confirmado:
        return 'Confirmado';
      case GigStatus.facturado:
        return 'Facturado';
      case GigStatus.cobrado:
        return 'Cobrado';
      case GigStatus.confirmadoB:
        return 'Confirmado en B';
      case GigStatus.realizadoB:
        return 'Realizado en B';
      case GigStatus.cobradoB:
        return 'Cobrado en B';
      case GigStatus.cancelado:
        return 'Cancelado';
    }
  }

  String get dbValue {
    switch (this) {
      case GigStatus.confirmado:
        return 'confirmado';
      case GigStatus.facturado:
        return 'facturado';
      case GigStatus.cobrado:
        return 'cobrado';
      case GigStatus.confirmadoB:
        return 'confirmado_b';
      case GigStatus.realizadoB:
        return 'realizado_b';
      case GigStatus.cobradoB:
        return 'cobrado_b';
      case GigStatus.cancelado:
        return 'cancelado';
    }
  }

  static GigStatus fromDb(String value) {
    switch (value) {
      case 'confirmado':
        return GigStatus.confirmado;
      case 'facturado':
        return GigStatus.facturado;
      case 'cobrado':
        return GigStatus.cobrado;
      case 'confirmado_b':
        return GigStatus.confirmadoB;
      case 'realizado_b':
        return GigStatus.realizadoB;
      case 'cobrado_b':
        return GigStatus.cobradoB;
      // Compatibilidad estados antiguos
      case 'pendiente':
        return GigStatus.confirmado;
      case 'factura_generada':
        return GigStatus.confirmado;
      case 'factura_enviada':
        return GigStatus.facturado;
      case 'pagado':
        return GigStatus.cobrado;
      case 'cancelado':
        return GigStatus.cancelado;
      case 'cobrado_en_b':
        return GigStatus.cobradoB;
      default:
        return GigStatus.confirmado;
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
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Gig({
    String? id,
    required this.fecha,
    required this.clientId,
    this.notas,
    this.cachet,
    this.facturable = true,
    this.status = GigStatus.confirmado,
    this.invoiceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Gig copyWith({
    DateTime? fecha,
    String? clientId,
    String? notas,
    double? cachet,
    bool? facturable,
    GigStatus? status,
    String? invoiceId,
    DateTime? updatedAt,
    DateTime? deletedAt,
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
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Gig touch() => copyWith(updatedAt: DateTime.now());

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
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };
  }

  factory Gig.fromMap(Map<String, dynamic> map) {
    final facturable = (map['facturable'] as int) == 1;
    var status = GigStatusExtension.fromDb(map['status'] as String);
    // Compatibilidad con datos antiguos: "pendiente" en bolos en B
    // debe leerse como "confirmado_b".
    if (!facturable && status == GigStatus.confirmado) {
      status = GigStatus.confirmadoB;
    }
    return Gig(
      id: map['id'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      clientId: map['client_id'] as String,
      notas: map['notas'] as String?,
      cachet: map['cachet'] != null ? (map['cachet'] as num).toDouble() : null,
      facturable: facturable,
      status: status,
      invoiceId: map['invoice_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(
        (map['updated_at'] ?? map['created_at']) as String,
      ),
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
    );
  }
}
