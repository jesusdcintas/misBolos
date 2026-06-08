class PeriodUtils {
  const PeriodUtils._();

  static int quarterOfMonth(int month) => ((month - 1) ~/ 3) + 1;

  static int currentQuarter([DateTime? now]) {
    final date = now ?? DateTime.now();
    return quarterOfMonth(date.month);
  }

  static (DateTime, DateTime) monthRange(int year, int month) {
    final from = DateTime(year, month, 1);
    final to = DateTime(year, month + 1, 0, 23, 59, 59);
    return (from, to);
  }

  static (DateTime, DateTime) quarterRange(int year, int quarter) {
    final startMonth = (quarter - 1) * 3 + 1;
    final from = DateTime(year, startMonth, 1);
    final to = DateTime(year, startMonth + 3, 0, 23, 59, 59);
    return (from, to);
  }

  static (DateTime, DateTime) yearRange(int year) {
    final from = DateTime(year, 1, 1);
    final to = DateTime(year, 12, 31, 23, 59, 59);
    return (from, to);
  }
}
