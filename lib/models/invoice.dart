import 'dart:convert';
import 'package:uuid/uuid.dart';

enum InvoiceStatus { borrador, enviada, pagada }

extension InvoiceStatusExtension on InvoiceStatus {
  String get label {
    switch (this) {
      case InvoiceStatus.borrador:
        return 'Borrador';
      case InvoiceStatus.enviada:
        return 'Enviada';
      case InvoiceStatus.pagada:
        return 'Pagada';
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
  })  : id = id ?? const Uuid().v4(),
        ivaAmount = ivaAmount ?? (subtotal * ivaRate),
        irpfAmount = irpfAmount ?? (subtotal * irpfRate),
        total = total ?? (subtotal + (ivaAmount ?? subtotal * ivaRate) - (irpfAmount ?? subtotal * irpfRate)),
        createdAt = createdAt ?? DateTime.now();

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
    );
  }

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
    );
  }
}
