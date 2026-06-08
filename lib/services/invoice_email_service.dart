import 'dart:convert';

import '../models/app_settings.dart';
import '../models/client.dart';
import '../models/invoice.dart';
import '../core/utils/invoice_file_name.dart';
import 'pdf_service.dart';
import 'supabase_service.dart';

class InvoiceEmailService {
  static const provider = 'supabase_edge_function';
  static const functionName = 'send-invoice-email';

  Future<void> sendInvoice({
    required Invoice invoice,
    required Client client,
    required AppSettings settings,
  }) async {
    final recipient = client.email?.trim() ?? '';
    if (recipient.isEmpty) {
      throw InvoiceEmailException('El cliente no tiene email configurado.');
    }
    if (!SupabaseService.instance.isAuthenticated) {
      throw InvoiceEmailException(
        'Inicia sesión en Supabase antes de enviar facturas por email.',
      );
    }

    final file = await PdfService().generateInvoicePdf(
      invoice: invoice,
      client: client,
      settings: settings,
    );
    final bytes = await file.readAsBytes();
    final subject = buildSubject(invoice);

    final response = await SupabaseService.instance.invokeFunction(
      functionName,
      body: {
        'invoiceId': invoice.id,
        'invoiceNumber': invoice.numero,
        'clientId': client.id,
        'recipientEmail': recipient,
        'subject': subject,
        'fileName': buildInvoicePdfFileName(
          invoice: invoice,
          clientName: client.nombre,
        ),
        'pdfBase64': base64Encode(bytes),
      },
    );

    if (response is Map && response['ok'] == false) {
      throw InvoiceEmailException(
        response['error']?.toString() ?? 'No se pudo enviar el email.',
      );
    }
  }

  String buildSubject(Invoice invoice) {
    return invoice.isRectifying
        ? 'Factura rectificativa ${invoice.visualNumber}'
        : 'Factura ${invoice.visualNumber}';
  }
}

class InvoiceEmailException implements Exception {
  final String message;
  InvoiceEmailException(this.message);

  @override
  String toString() => message;
}
