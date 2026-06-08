import 'package:uuid/uuid.dart';

enum InvoiceEmailStatus { pending, sent, failed }

extension InvoiceEmailStatusExtension on InvoiceEmailStatus {
  String get dbValue => name;

  static InvoiceEmailStatus fromDb(String value) {
    return InvoiceEmailStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => InvoiceEmailStatus.pending,
    );
  }
}

class InvoiceEmailLog {
  final String id;
  final String invoiceId;
  final String clientId;
  final String recipientEmail;
  final String provider;
  final String subject;
  final InvoiceEmailStatus status;
  final String? errorMessage;
  final DateTime? sentAt;
  final DateTime createdAt;

  InvoiceEmailLog({
    String? id,
    required this.invoiceId,
    required this.clientId,
    required this.recipientEmail,
    required this.provider,
    required this.subject,
    this.status = InvoiceEmailStatus.pending,
    this.errorMessage,
    this.sentAt,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  InvoiceEmailLog copyWith({
    InvoiceEmailStatus? status,
    String? errorMessage,
    DateTime? sentAt,
  }) {
    return InvoiceEmailLog(
      id: id,
      invoiceId: invoiceId,
      clientId: clientId,
      recipientEmail: recipientEmail,
      provider: provider,
      subject: subject,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      sentAt: sentAt ?? this.sentAt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'client_id': clientId,
      'recipient_email': recipientEmail,
      'provider': provider,
      'subject': subject,
      'status': status.dbValue,
      'error_message': errorMessage,
      'sent_at': sentAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory InvoiceEmailLog.fromMap(Map<String, dynamic> map) {
    return InvoiceEmailLog(
      id: map['id'] as String,
      invoiceId: map['invoice_id'] as String,
      clientId: map['client_id'] as String,
      recipientEmail: map['recipient_email'] as String,
      provider: map['provider'] as String,
      subject: map['subject'] as String,
      status: InvoiceEmailStatusExtension.fromDb(map['status'] as String),
      errorMessage: map['error_message'] as String?,
      sentAt: map['sent_at'] != null
          ? DateTime.parse(map['sent_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
