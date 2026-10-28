import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  static final _displayFormat = DateFormat('dd/MM/yyyy');
  static final _shortFormat = DateFormat('dd MMM', 'es');
  static final _monthYearFormat = DateFormat('MMMM yyyy', 'es');
  static final _dayOfWeek = DateFormat('EEEE dd MMM', 'es');
  static final _dayOfWeekFull = DateFormat('EEEE dd/MM/yyyy', 'es');
  static final _isoDayFormat = DateFormat('yyyy-MM-dd');

  static String display(DateTime date) => _displayFormat.format(date);
  static String short(DateTime date) => _shortFormat.format(date);
  static String monthYear(DateTime date) => _monthYearFormat.format(date);
  static String dayOfWeek(DateTime date) => _dayOfWeek.format(date);

  /// Formato yyyy-MM-dd, para pasar un día en una ruta.
  static String isoDay(DateTime date) => _isoDayFormat.format(date);

  /// Lee un día en formato yyyy-MM-dd y lo normaliza a medianoche local.
  /// Devuelve null si no llega valor o no es una fecha válida.
  static DateTime? parseIsoDay(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    // Descarta fechas que no existen y que DateTime desbordaría (31/02, 00/00).
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }
  
  /// Formato: Sábado 04/04/2026
  static String dayOfWeekFull(DateTime date) {
    final formatted = _dayOfWeekFull.format(date);
    // Capitalizar primera letra
    return formatted[0].toUpperCase() + formatted.substring(1);
  }
  
  static String relative(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);
    
    if (diff.inDays == 0) return 'Hoy';
    if (diff.inDays == 1) return 'Mañana';
    if (diff.inDays == -1) return 'Ayer';
    if (diff.inDays > 0 && diff.inDays <= 7) return 'En ${diff.inDays} días';
    return display(date);
  }
}
