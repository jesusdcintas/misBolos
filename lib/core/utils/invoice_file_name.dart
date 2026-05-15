import '../../models/invoice.dart';

String buildInvoicePdfFileName({
  required Invoice invoice,
  required String? clientName,
}) {
  final number = invoice.numero.toString().padLeft(3, '0');
  final date = _formatDate(invoice.fecha);
  final customer = (clientName == null || clientName.trim().isEmpty)
      ? 'Sin cliente'
      : clientName.trim();
  return sanitizeFileName('FACTURA $number - $customer - $date.pdf');
}

String sanitizeFileName(String input) {
  final sanitized = input
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (sanitized.length <= 120) return sanitized;
  return sanitized.substring(0, 120).trim();
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

