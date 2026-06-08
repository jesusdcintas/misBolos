import 'dart:convert';

import 'package:uuid/uuid.dart';

enum FiscalRecordType { issue, rectification, cancellation }

extension FiscalRecordTypeExtension on FiscalRecordType {
  String get dbValue => name;

  static FiscalRecordType fromDb(String value) {
    switch (value) {
      case 'rectification':
        return FiscalRecordType.rectification;
      case 'cancellation':
        return FiscalRecordType.cancellation;
      case 'issue':
      default:
        return FiscalRecordType.issue;
    }
  }
}

enum AeatStatus { notSent, pending, sent, accepted, rejected, error }

extension AeatStatusExtension on AeatStatus {
  String get dbValue {
    switch (this) {
      case AeatStatus.notSent:
        return 'not_sent';
      case AeatStatus.pending:
        return 'pending';
      case AeatStatus.sent:
        return 'sent';
      case AeatStatus.accepted:
        return 'accepted';
      case AeatStatus.rejected:
        return 'rejected';
      case AeatStatus.error:
        return 'error';
    }
  }

  static AeatStatus fromDb(String value) {
    switch (value) {
      case 'pending':
        return AeatStatus.pending;
      case 'sent':
        return AeatStatus.sent;
      case 'accepted':
        return AeatStatus.accepted;
      case 'rejected':
        return AeatStatus.rejected;
      case 'error':
        return AeatStatus.error;
      case 'not_sent':
      default:
        return AeatStatus.notSent;
    }
  }
}

class InvoiceFiscalRecord {
  final String id;
  final String? userId;
  final String invoiceId;
  final FiscalRecordType recordType;
  final String invoiceNumber;
  final String invoiceSeries;
  final DateTime issuedAt;
  final String? previousHash;
  final String currentHash;
  final Map<String, dynamic> payloadJson;
  final AeatStatus aeatStatus;
  final String? aeatError;
  final DateTime createdAt;

  InvoiceFiscalRecord({
    String? id,
    this.userId,
    required this.invoiceId,
    required this.recordType,
    required this.invoiceNumber,
    this.invoiceSeries = '',
    required this.issuedAt,
    this.previousHash,
    required this.currentHash,
    required this.payloadJson,
    this.aeatStatus = AeatStatus.notSent,
    this.aeatError,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'invoice_id': invoiceId,
      'record_type': recordType.dbValue,
      'invoice_number': invoiceNumber,
      'invoice_series': invoiceSeries,
      'issued_at': issuedAt.toIso8601String(),
      'previous_hash': previousHash,
      'current_hash': currentHash,
      'payload_json': jsonEncode(payloadJson),
      'aeat_status': aeatStatus.dbValue,
      'aeat_error': aeatError,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory InvoiceFiscalRecord.fromMap(Map<String, dynamic> map) {
    final payloadRaw = map['payload_json'];
    final payload = payloadRaw is String
        ? jsonDecode(payloadRaw) as Map<String, dynamic>
        : Map<String, dynamic>.from(payloadRaw as Map? ?? {});
    return InvoiceFiscalRecord(
      id: map['id'] as String,
      userId: map['user_id'] as String?,
      invoiceId: map['invoice_id'] as String,
      recordType: FiscalRecordTypeExtension.fromDb(
        map['record_type'] as String,
      ),
      invoiceNumber: map['invoice_number'] as String,
      invoiceSeries: map['invoice_series'] as String? ?? '',
      issuedAt: DateTime.parse(map['issued_at'] as String),
      previousHash: map['previous_hash'] as String?,
      currentHash: map['current_hash'] as String,
      payloadJson: payload,
      aeatStatus: AeatStatusExtension.fromDb(
        map['aeat_status'] as String? ?? 'not_sent',
      ),
      aeatError: map['aeat_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
