import '../../database/database_helper.dart';
import '../../models/invoice.dart';

class InvoiceNumberGenerator {
  InvoiceNumberGenerator._();

  static Future<int> nextNumber({int? year}) async {
    final db = await DatabaseHelper.instance.database;
    final invoiceYear = year ?? DateTime.now().year;
    final result = await db.rawQuery(
      '''
      SELECT MAX(numero) as max_num
      FROM invoices
      WHERE CAST(strftime('%Y', fecha) AS INTEGER) = ?
        AND deleted_at IS NULL
        AND invoice_type = ?
      ''',
      [invoiceYear, InvoiceType.normal.dbValue],
    );
    final maxNum = result.first['max_num'] as int?;
    return (maxNum ?? 0) + 1;
  }
}
