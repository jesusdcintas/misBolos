import '../../database/database_helper.dart';

class InvoiceNumberGenerator {
  InvoiceNumberGenerator._();

  static Future<int> nextNumber() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('SELECT MAX(numero) as max_num FROM invoices');
    final maxNum = result.first['max_num'] as int?;
    return (maxNum ?? 0) + 1;
  }
}
