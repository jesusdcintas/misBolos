import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/invoice.dart';
import '../models/invoice_fiscal_record.dart';

class InvoiceFiscalRecordRepository {
  static final InvoiceFiscalRecordRepository instance =
      InvoiceFiscalRecordRepository._();
  InvoiceFiscalRecordRepository._();

  Future<InvoiceFiscalRecord> createForInvoiceIssue(
    DatabaseExecutor db,
    Invoice invoice, {
    required String? userId,
  }) async {
    final recordType = invoice.isRectifying
        ? FiscalRecordType.rectification
        : FiscalRecordType.issue;
    final previousHash = await _latestHash(
      db,
      userId: userId,
      invoiceSeries: invoice.visualSeries,
    );
    final issuedAt = DateTime.now();
    final payload = _payloadFor(invoice, previousHash: previousHash);
    final currentHash = sha256
        .convert(utf8.encode(jsonEncode(_stable(payload))))
        .toString();
    final record = InvoiceFiscalRecord(
      userId: userId,
      invoiceId: invoice.id,
      recordType: recordType,
      invoiceNumber: invoice.numero.toString(),
      invoiceSeries: invoice.visualSeries,
      issuedAt: issuedAt,
      previousHash: previousHash,
      currentHash: currentHash,
      payloadJson: payload,
    );
    await db.insert('invoice_fiscal_records', record.toMap());
    return record;
  }

  Future<InvoiceFiscalRecord?> getById(String id) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'invoice_fiscal_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return InvoiceFiscalRecord.fromMap(rows.first);
  }

  Future<String?> _latestHash(
    DatabaseExecutor db, {
    required String? userId,
    required String invoiceSeries,
  }) async {
    final rows = await db.query(
      'invoice_fiscal_records',
      columns: ['current_hash'],
      where: userId == null
          ? 'invoice_series = ?'
          : 'user_id = ? AND invoice_series = ?',
      whereArgs: userId == null ? [invoiceSeries] : [userId, invoiceSeries],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['current_hash'] as String?;
  }

  Map<String, dynamic> _payloadFor(
    Invoice invoice, {
    required String? previousHash,
  }) {
    return {
      'invoice_id': invoice.id,
      'invoice_number': invoice.numero.toString(),
      'invoice_series': invoice.visualSeries,
      'invoice_date': invoice.fecha.toIso8601String().split('T').first,
      'client_id': invoice.clientId,
      'subtotal': invoice.subtotal,
      'iva_rate': invoice.ivaRate,
      'iva_amount': invoice.ivaAmount,
      'irpf_rate': invoice.irpfRate,
      'irpf_amount': invoice.irpfAmount,
      'total': invoice.total,
      'status': invoice.status.dbValue,
      'invoice_type': invoice.invoiceType.dbValue,
      'rectifies_invoice_id': invoice.rectifiesInvoiceId,
      'rectification_type': invoice.rectificationType?.dbValue,
      'rectification_reason': invoice.rectificationReason,
      'original_invoice_number': invoice.originalInvoiceNumber,
      'original_invoice_date': invoice.originalInvoiceDate
          ?.toIso8601String()
          .split('T')
          .first,
      'items': invoice.items.map((item) => item.toMap()).toList(),
      'previous_hash': previousHash,
    };
  }

  Object? _stable(Object? value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((key) => key.toString()).toList()
        ..sort();
      return {
        for (final key in sortedKeys)
          key: _stable(
            value.entries
                .firstWhere((entry) => entry.key.toString() == key)
                .value,
          ),
      };
    }
    if (value is List) return value.map(_stable).toList();
    return value;
  }
}
