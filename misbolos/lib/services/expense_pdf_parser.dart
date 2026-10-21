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
  static final _amountWithDecimalRegex = RegExp(r'\d[\d.,]*[.,]\d{1,2}');
  static final _totalLabelRegex = RegExp(
    r'(total\s*:|total\s+factura|total\s+amount|importe\s+total|'
    r'total\s+a\s+pagar|^total\b)',
    caseSensitive: false,
  );
  static final _totalExcluidoRegex = RegExp(
    r'\b(subtotal|total\s+price|value\s+of\s+goods|net\s+amount|base|iva|vat|'
    r'carried\s+forward|amount\s+carried\s+forward|mastercard|visa|'
    r'base\s+imponible|importe\s+del\s+producto\s*\(\s*base\s*imponible\s*\))\b',
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

  static final _formaSocietariaRegex = RegExp(
    r'(?<![A-Za-zÁÉÍÓÚÜÑáéíóúüñ])'
    r'(S\.\s?L\.\s?U\.?|S\.\s?L\.\s?L\.?|S\.\s?L\.?|S\.\s?A\.?|SLU|SLL|SL|SA|GmbH)'
    r'(?![A-Za-zÁÉÍÓÚÜÑáéíóúüñ])',
  );
  static final _direccionRegex = RegExp(
    r'\b(calle|c/|avda|avenida|av\.|plaza|pza|paseo|carretera|ctra|camino|'
    r'street|str\.|strasse|straße|road|pol[ií]gono|apartado)|\b\d{5}\b',
    caseSensitive: false,
  );

  static ExpensePdfParseResult parse(
    String texto, {
    String? nifUsuario,
    String? nombreUsuario,
  }) {
    final lineas = texto
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .toList();
    return ExpensePdfParseResult(
      fecha: _parseFecha(lineas),
      total: _parseTotal(lineas),
      proveedor: _parseProveedor(
        lineas,
        _lineasDelUsuario(lineas, nifUsuario, nombreUsuario),
        _normalizarTexto(nombreUsuario ?? ''),
      ),
    );
  }

  /// Índices de las líneas del bloque donde aparece el NIF o el nombre del
  /// usuario (el adquiriente), que nunca pueden ser proveedor.
  static Set<int> _lineasDelUsuario(
    List<String> lineas,
    String? nifUsuario,
    String? nombreUsuario,
  ) {
    final nif = _normalizarNif(nifUsuario ?? '');
    final nombre = _normalizarTexto(nombreUsuario ?? '');
    final excluidas = <int>{};
    for (var i = 0; i < lineas.length; i++) {
      final esNif = nif.length >= 8 && _normalizarNif(lineas[i]).contains(nif);
      final esNombre =
          nombre.length >= 3 && _normalizarTexto(lineas[i]).contains(nombre);
      if (!esNif && !esNombre) continue;
      excluidas.add(i);
      // El NIF suele cerrar el bloque del adquiriente y el nombre abrirlo.
      final arriba = esNif ? 3 : 1;
      final abajo = esNif && !esNombre ? 1 : 3;
      for (var d = 1; d <= arriba; d++) {
        if (i - d < 0 || lineas[i - d].isEmpty) break;
        excluidas.add(i - d);
      }
      for (var d = 1; d <= abajo; d++) {
        if (i + d >= lineas.length || lineas[i + d].isEmpty) break;
        excluidas.add(i + d);
      }
    }
    return excluidas;
  }

  static String _normalizarNif(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[\s.\-]'), '');

  static String _normalizarTexto(String s) {
    const conAcento = 'áéíóúüàèìòù';
    const sinAcento = 'aeiouuaeiou';
    var out = s.toLowerCase();
    for (var i = 0; i < conAcento.length; i++) {
      out = out.replaceAll(conAcento[i], sinAcento[i]);
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static final _fechaNoEmisionRegex = RegExp(
    r'operacion|vencimiento|due\s+date|\bf\.\s*op',
  );
  static final _fechaEmisionRegex = RegExp(
    r'fecha\s*(de\s+)?(factura|emision|expedicion)|invoice\s+date',
  );
  static final _fechaEtiquetaRegex = RegExp(r'\bfecha\b|\bdate\b');

  static CampoSugerido<DateTime> _parseFecha(List<String> lineas) {
    final emision = <DateTime>{};
    final etiquetadas = <DateTime>{};
    final todas = <DateTime>{};

    for (var i = 0; i < lineas.length; i++) {
      final linea = lineas[i];
      var inicio = 0;
      for (final m in _dateRegex.allMatches(linea)) {
        final fecha = _fechaDe(m);
        // Cada fecha toma como etiqueta el texto entre la fecha anterior y ella.
        var contexto = linea.substring(inicio, m.start);
        inicio = m.end;
        if (fecha == null) continue;
        todas.add(fecha);
        if (contexto.trim().isEmpty && i > 0) {
          final previa = lineas[i - 1];
          if (previa.isNotEmpty && !_dateRegex.hasMatch(previa)) {
            contexto = previa;
          }
        }
        final ctx = _normalizarTexto(contexto);
        if (_fechaNoEmisionRegex.hasMatch(ctx)) continue;
        if (_fechaEmisionRegex.hasMatch(ctx)) {
          emision.add(fecha);
        } else if (_fechaEtiquetaRegex.hasMatch(ctx)) {
          etiquetadas.add(fecha);
        }
      }
    }

    for (final candidatas in [emision, etiquetadas]) {
      if (candidatas.length == 1) {
        return CampoSugerido.encontrado(candidatas.first);
      }
      if (candidatas.length > 1) return const CampoSugerido.vacio();
    }
    if (todas.length == 1) return CampoSugerido.encontrado(todas.first);
    return const CampoSugerido.vacio();
  }

  static DateTime? _fechaDe(RegExpMatch m) {
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, mo, d);
    if (date.month != mo || date.day != d) return null;
    return date;
  }

  static CampoSugerido<double> _parseTotal(List<String> lineas) {
    final importesDocumento = _extraerImportesDocumentoEnCentimos(lineas);
    final candidatosValidados = <int>{};
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
      if (valor == null) continue;
      final candidato = (valor * 100).round();
      if (_coincideConSumaDeDosImportes(candidato, importesDocumento)) {
        candidatosValidados.add(candidato);
      }
    }
    if (candidatosValidados.length == 1) {
      return CampoSugerido.encontrado(candidatosValidados.first / 100);
    }
    return const CampoSugerido.vacio();
  }

  static List<int> _extraerImportesDocumentoEnCentimos(List<String> lineas) {
    final importes = <int>[];
    for (final linea in lineas) {
      final sinFechas = linea.replaceAll(_dateRegex, ' ');
      for (final m in _amountTokenRegex.allMatches(sinFechas)) {
        final raw = m.group(0)!;
        if (!_amountWithDecimalRegex.hasMatch(raw)) continue;
        final valor = parseImporte(raw);
        if (valor == null || valor <= 0) continue;
        importes.add((valor * 100).round());
      }
    }
    return importes;
  }

  static bool _coincideConSumaDeDosImportes(int candidato, List<int> importes) {
    if (importes.length < 2) return false;
    for (var i = 0; i < importes.length - 1; i++) {
      for (var j = i + 1; j < importes.length; j++) {
        final a = importes[i];
        final b = importes[j];
        if (a == b) continue; // Deben ser dos importes distintos.
        if ((a + b - candidato).abs() <= 1) return true;
      }
    }
    return false;
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

  static CampoSugerido<String> _parseProveedor(
    List<String> lineas,
    Set<int> excluidas,
    String nombreUsuario,
  ) {
    bool disponible(int i) => lineas[i].isNotEmpty && !excluidas.contains(i);
    bool esDelUsuario(String nombre) =>
        nombreUsuario.length >= 3 &&
        _normalizarTexto(nombre).contains(nombreUsuario);

    final societarias = <String, String>{};
    for (var i = 0; i < lineas.length; i++) {
      if (!disponible(i)) continue;
      final nombre = _nombreSocietario(lineas[i]);
      if (nombre == null || esDelUsuario(nombre)) continue;
      societarias.putIfAbsent(_normalizarTexto(nombre), () => nombre);
    }
    if (societarias.length == 1) {
      return CampoSugerido.encontrado(societarias.values.first);
    }
    if (societarias.length > 1) return const CampoSugerido.vacio();

    CampoSugerido<String> candidata(String linea) {
      final valida = _esNombreValido(linea) &&
          !_direccionRegex.hasMatch(linea) &&
          !esDelUsuario(linea);
      return valida
          ? CampoSugerido.encontrado(linea)
          : const CampoSugerido.vacio();
    }

    final nifIndex = List.generate(lineas.length, (i) => i).firstWhere(
      (i) =>
          disponible(i) &&
          (_nifLabelRegex.hasMatch(lineas[i]) ||
              _nifValueRegex.hasMatch(lineas[i])),
      orElse: () => -1,
    );
    if (nifIndex >= 0) {
      for (var i = nifIndex - 1; i >= 0; i--) {
        if (lineas[i].isEmpty) continue;
        if (excluidas.contains(i)) return const CampoSugerido.vacio();
        return candidata(lineas[i]);
      }
      return const CampoSugerido.vacio();
    }

    for (var i = 0; i < lineas.length; i++) {
      if (!disponible(i)) continue;
      return candidata(lineas[i]);
    }
    return const CampoSugerido.vacio();
  }

  /// Nombre comercial hasta la forma societaria, sin la dirección que siga.
  static String? _nombreSocietario(String linea) {
    final match = _formaSocietariaRegex.firstMatch(linea);
    if (match == null) return null;
    var nombre = linea.substring(0, match.end).trim();
    final dosPuntos = nombre.lastIndexOf(':');
    if (dosPuntos >= 0) nombre = nombre.substring(dosPuntos + 1).trim();
    final sinForma = nombre.substring(0, nombre.length - match.group(0)!.length);
    if (!RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]{2,}').hasMatch(sinForma)) {
      return null;
    }
    return _esNombreValido(nombre) ? nombre : null;
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
