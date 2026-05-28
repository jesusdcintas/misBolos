class DateResolverService {
  DateResolverService._();

  static final DateResolverService instance = DateResolverService._();

  static const _weekdayMap = <String, int>{
    'lunes': DateTime.monday,
    'martes': DateTime.tuesday,
    'miercoles': DateTime.wednesday,
    'miércoles': DateTime.wednesday,
    'jueves': DateTime.thursday,
    'viernes': DateTime.friday,
    'sabado': DateTime.saturday,
    'sábado': DateTime.saturday,
    'domingo': DateTime.sunday,
  };

  DateTime? resolveExpression(
    String expression, {
    required DateTime now,
  }) {
    final text = expression.trim().toLowerCase();
    if (text.isEmpty) return null;
    final today = DateTime(now.year, now.month, now.day);
    if (text == 'hoy') return today;
    if (text == 'mañana' || text == 'manana') {
      return today.add(const Duration(days: 1));
    }
    if (text == 'pasado mañana' || text == 'pasado manana') {
      return today.add(const Duration(days: 2));
    }
    for (final entry in _weekdayMap.entries) {
      if (text.contains(entry.key)) {
        return _nextWeekday(today, entry.value);
      }
    }
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    return null;
  }

  List<String> extractRelativeDateTokens(String source) {
    final text = source.toLowerCase();
    final tokens = <String>[];
    final relative = RegExp(r'\b(hoy|mañana|manana|pasado mañana|pasado manana)\b');
    for (final m in relative.allMatches(text)) {
      tokens.add(m.group(1)!);
    }
    final weekdays = RegExp(
      r'\b(lunes|martes|miercoles|miércoles|jueves|viernes|sabado|sábado|domingo)\b',
    );
    for (final m in weekdays.allMatches(text)) {
      tokens.add(m.group(1)!);
    }
    return tokens;
  }

  DateTime _nextWeekday(DateTime start, int targetWeekday) {
    final current = start.weekday;
    var diff = targetWeekday - current;
    if (diff <= 0) diff += 7;
    return start.add(Duration(days: diff));
  }
}
