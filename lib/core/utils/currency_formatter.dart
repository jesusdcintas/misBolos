import 'package:intl/intl.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static final _euroFormat = NumberFormat.currency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: 2,
  );

  static final _compactFormat = NumberFormat.compactCurrency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: 0,
  );

  static String format(double amount) => _euroFormat.format(amount);
  static String compact(double amount) => _compactFormat.format(amount);
  static String formatNoSymbol(double amount) =>
      NumberFormat('#,##0.00', 'es_ES').format(amount);
}
