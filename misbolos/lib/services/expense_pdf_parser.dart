/// Campo sugerido por el parser. Si [encontrado] es false, [valor] es null.
class CampoSugerido<T> {
  final T? valor;
  final bool encontrado;

  const CampoSugerido.encontrado(T this.valor) : encontrado = true;
  const CampoSugerido.vacio() : valor = null, encontrado = false;
}

class ExpensePdfParseResult {
  final CampoSugerido<DateTime> fecha;
  final CampoSugerido<double> total;
  final CampoSugerido<String> proveedor;

  const ExpensePdfParseResult({
    required this.fecha,
    required this.total,
    required this.proveedor,
  });

  bool get algunoEncontrado =>
      fecha.encontrado || total.encontrado || proveedor.encontrado;
}

/// Parser local (sin IA) del texto de una factura en PDF.
///
/// Solo sugiere un campo cuando lo encuentra sin ambigüedad; nunca inventa
/// valores.
class ExpensePdfParser {
  const ExpensePdfParser._();

  static final _dateRegex = RegExp(
    r'(?<!\d)(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4})(?!\d)',
  );
  static final _amountTokenRegex = RegExp(r'\d[\d.,]*');
  static final _totalLabelRegex = RegExp(
    r'(total\s*:|total\s+factura|total\s+amount|importe\s+total|'
    r'total\s+a\s+pagar|^total\b)',
    caseSensitive: false,
  );
  static final _totalExcluidoRegex = RegExp(
    r'\b(subtotal|total\s+price|value\s+of\s+goods|net\s+amount|base|iva|vat|'
    r'carried\s+forward|mastercard|visa)\b',
    caseSensitive: false,
  );
  static final _soloEtiquetaRegex = RegExp(
    r'^(?:[\s:.\-€]|eur(?:os)?)*$',
    caseSensitive: false,
  );
  static final _nifLabelRegex = RegExp(
    r'\b(N\.?I\.?F\.?|C\.?I\.?F\.?)\b',
    caseSensitive: false,
  );
  static final _nifValueRegex = RegExp(
    r'\b([ABCDEFGHJNPQRSUVW]\d{7}[0-9A-J]|\d{8}[A-Z]|[XYZ]\d{7}[A-Z])\b',
  );
  static const _palabrasNoProveedor = [
    'factura',
    'invoice',
    'ticket',
    'recibo',
    'presupuesto',
    'albarán',
    'albaran',
    'fecha',
    'total',
    'nif',
    'cif',
    'página',
    'pagina',
  ];

  static ExpensePdfParseResult parse(String texto) {
    final lineas = texto
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .toList();
    return ExpensePdfParseResult(
      fecha: _parseFecha(lineas),
      total: _parseTotal(lineas),
      proveedor: _parseProveedor(lineas),
    );
  }

  static CampoSugerido<DateTime> _parseFecha(List<String> lineas) {
    final facturaCtx = <DateTime>{};
    final fechaCtx = <DateTime>{};
    final todas = <DateTime>{};

    for (var i = 0; i < lineas.length; i++) {
      final fechas = _fechasEn(lineas[i]);
      if (fechas.isEmpty) continue;
      todas.addAll(fechas);

      final ctx = lineas[i].toLowerCase();
      // Etiqueta "Fecha:" en la línea anterior y la fecha debajo.
      final prevLinea = i > 0 ? lineas[i - 1] : '';
      final etiquetaPrevia = prevLinea.isNotEmpty && _fechasEn(prevLinea).isEmpty
          ? prevLinea.toLowerCase()
          : '';
      final contexto = '$ctx $etiquetaPrevia';
      if (contexto.contains('vencimiento')) continue;
      if (RegExp(r'fecha\s+(de\s+)?(factura|emisi[oó]n|expedici[oó]n)')
          .hasMatch(contexto)) {
        facturaCtx.addAll(fechas);
      } else if (contexto.contains('fecha')) {
        fechaCtx.addAll(fechas);
      }
    }

    for (final candidatas in [facturaCtx, fechaCtx]) {
      if (candidatas.length == 1) {
        return CampoSugerido.encontrado(candidatas.first);
      }
      if (candidatas.length > 1) return const CampoSugerido.vacio();
    }
    if (todas.length == 1) return CampoSugerido.encontrado(todas.first);
    return const CampoSugerido.vacio();
  }

  static List<DateTime> _fechasEn(String linea) {
    final result = <DateTime>[];
    for (final m in _dateRegex.allMatches(linea)) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final y = int.parse(m.group(3)!);
      if (mo < 1 || mo > 12 || d < 1 || d > 31) continue;
      final date = DateTime(y, mo, d);
      if (date.month != mo || date.day != d) continue;
      result.add(date);
    }
    return result;
  }

  static CampoSugerido<double> _parseTotal(List<String> lineas) {
    final candidatos = <int>{};
    for (var i = 0; i < lineas.length; i++) {
      final linea = lineas[i];
      final etiqueta = _totalLabelRegex.firstMatch(linea);
      if (etiqueta == null) continue;
      if (_totalExcluidoRegex.hasMatch(linea)) continue;

      final resto = linea.substring(etiqueta.end);
      var valor = _ultimoImporte(resto);
      if (valor == null && _soloEtiquetaRegex.hasMatch(resto)) {
        final siguiente = _siguienteNoVacia(lineas, i);
        if (siguiente != null && !_totalExcluidoRegex.hasMatch(siguiente)) {
          valor = _ultimoImporte(siguiente);
        }
      }
      if (valor != null) candidatos.add((valor * 100).round());
    }
    if (candidatos.length == 1) {
      return CampoSugerido.encontrado(candidatos.first / 100);
    }
    return const CampoSugerido.vacio();
  }

  static double? _ultimoImporte(String texto) {
    final sinFechas = texto.replaceAll(_dateRegex, ' ');
    final tokens = _amountTokenRegex
        .allMatches(sinFechas)
        .map((m) => m.group(0)!)
        .toList();
    if (tokens.isEmpty) return null;
    return parseImporte(tokens.last);
  }

  static String? _siguienteNoVacia(List<String> lineas, int desde) {
    for (var j = desde + 1; j < lineas.length; j++) {
      if (lineas[j].isNotEmpty) return lineas[j];
    }
    return null;
  }

  /// Interpreta `1.234,56`, `1234,56`, `1,234.56` y `1234.56`.
  static double? parseImporte(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[.,]+$'), '');
    if (s.isEmpty) return null;
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    if (lastComma >= 0 && lastDot >= 0) {
      final decimalSep = lastComma > lastDot ? ',' : '.';
      final thousandsSep = decimalSep == ',' ? '.' : ',';
      s = s.replaceAll(thousandsSep, '').replaceAll(decimalSep, '.');
    } else if (lastComma >= 0) {
      s = RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(s)
          ? s.replaceAll(',', '')
          : s.replaceAll(',', '.');
    } else if (lastDot >= 0) {
      if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
        s = s.replaceAll('.', '');
      }
    }
    return double.tryParse(s);
  }

  static CampoSugerido<String> _parseProveedor(List<String> lineas) {
    final nifIndex = lineas.indexWhere(
      (l) => _nifLabelRegex.hasMatch(l) || _nifValueRegex.hasMatch(l),
    );
    if (nifIndex >= 0) {
      for (var i = nifIndex - 1; i >= 0; i--) {
        if (lineas[i].isEmpty) continue;
        return _esNombreValido(lineas[i])
            ? CampoSugerido.encontrado(lineas[i])
            : const CampoSugerido.vacio();
      }
      return const CampoSugerido.vacio();
    }

    for (final linea in lineas) {
      if (linea.isEmpty) continue;
      return _esNombreValido(linea)
          ? CampoSugerido.encontrado(linea)
          : const CampoSugerido.vacio();
    }
    return const CampoSugerido.vacio();
  }

  static bool _esNombreValido(String linea) {
    if (linea.length < 2 || linea.length > 80) return false;
    if (!RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(linea)) return false;
    if (_dateRegex.hasMatch(linea)) return false;
    if (_nifValueRegex.hasMatch(linea) || _nifLabelRegex.hasMatch(linea)) {
      return false;
    }
    final lower = linea.toLowerCase();
    return !_palabrasNoProveedor.any(lower.startsWith);
  }
}
