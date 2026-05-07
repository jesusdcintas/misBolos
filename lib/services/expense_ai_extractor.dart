import '../models/expense.dart';
import '../models/expense_extraction_result.dart';
import 'ai_service.dart';
import 'ai_attachment_service.dart';

class ExpenseAiExtractor {
  ExpenseAiExtractor._();

  static final ExpenseAiExtractor instance = ExpenseAiExtractor._();

  Future<ExpenseExtractionResult> extractExpenseFromText(String text) async {
    final extracted = await AiService.instance.extractExpenseFromText(
      message:
          'Extrae los campos de gasto desde este texto y devuelve JSON estricto.',
      contextData: {'raw_text': text},
    );
    return _toResult(extracted, sourceText: text);
  }

  Future<ExpenseExtractionResult> extractExpenseFromReceiptText({
    required String prompt,
    required String receiptText,
  }) async {
    final extracted = await AiService.instance.extractExpenseFromReceiptText(
      message: prompt,
      imageText: receiptText,
      contextData: {'source': 'ocr_text'},
    );
    return _toResult(extracted, sourceText: receiptText);
  }

  Future<ExpenseExtractionResult> extractExpenseFromImagePath(String path) async {
    final prepared = await AiAttachmentService.instance.imageToBase64(path);
    final extracted = await AiService.instance.extractExpenseFromImage(
      message:
          'Extrae un gasto desde esta imagen de ticket/factura. Devuelve solo JSON válido y no inventes datos.',
      imageBase64: prepared.base64Data,
      imageMimeType: prepared.mimeType,
      contextData: {
        'source': 'image',
        'file_name': path.split('/').last,
      },
    );
    return _toResult(extracted, sourceText: '');
  }

  ExpenseExtractionResult _toResult(
    Map<String, dynamic> map, {
    required String sourceText,
  }) {
    final detectedDates = _detectSpanishDates(sourceText);
    final merchant = _readString(map['merchant']);
    final station = _normalizeStation(_readString(map['station']), merchant);
    final invoiceNumber = _readString(map['invoice_number']);
    final concept = _readString(map['concept']);
    final discount = _readDouble(map['discount_amount']);
    final liters = _readDouble(map['liters']);
    final pricePerLiter = _readDouble(map['price_per_liter']);
    final vehiclePlate = _readString(map['vehicle_plate']);
    final notes = _buildNotes(
      station: station,
      invoiceNumber: invoiceNumber,
      operationDate: detectedDates.operationDate ??
          _readDate(map['operation_date']),
      discount: discount,
      liters: liters,
      pricePerLiter: pricePerLiter,
      vehiclePlate: vehiclePlate,
    );
    final total = _readDouble(map['total_amount']);
    final tax = _readDouble(map['tax_amount']);
    final base = _readDouble(map['base_amount']);
    var vatRate = _readDouble(map['vat_rate']);
    final deductibleRaw = map['is_deductible'] is bool
        ? map['is_deductible'] as bool
        : null;
    final deductiblePctRaw = _readDouble(map['deductible_percentage']);
    final warnings = _readWarnings(map['warnings']);
    final normalizedWarnings = warnings
        .where(
          (warning) =>
              !RegExp('importe del producto.*base_amount', caseSensitive: false)
                  .hasMatch(warning) &&
              !RegExp('producto usado como base', caseSensitive: false)
                  .hasMatch(warning),
        )
        .toList();
    final extractedConfidence = (_readDouble(map['confidence']) ?? 0).clamp(0, 1);
    final aiDate = _readDate(map['date']);
    final aiOperationDate = _readDate(map['operation_date']);
    final date = detectedDates.date ?? aiDate;
    final operationDate = detectedDates.operationDate ?? aiOperationDate;

    if (detectedDates.date != null && aiDate != null && detectedDates.date != aiDate) {
      normalizedWarnings.add(
        'Fecha corregida desde el campo "Fecha:" del documento.',
      );
    }
    if (date == null) {
      normalizedWarnings.add(
        'No se detectó una fecha clara; revisa la fecha manualmente.',
      );
    }

    if ((_readDouble(map['confidence']) ?? 0) < 0.75) {
      normalizedWarnings.add('Confianza baja: revisión manual obligatoria.');
    }
    if (deductibleRaw == true && deductiblePctRaw == 100 && concept != null) {
      final lower = concept.toLowerCase();
      if (lower.contains('gasolina') || lower.contains('combustible')) {
        normalizedWarnings.add(
          'No asumir deducción 100% en combustible sin validación fiscal.',
        );
      }
    }

    if ((vatRate == null || vatRate == 0) && base != null && tax != null) {
      vatRate = ((tax / base) * 100).roundToDouble();
    }

    final resolvedConcept = concept ?? merchant ?? 'Gasto';
    var resolvedCategory =
        _toCategory(_readString(map['category'])) ?? _inferCategory(
          concept: resolvedConcept,
          merchant: merchant,
        );
    var finalConcept = resolvedConcept;

    if (concept == null || concept.trim().isEmpty) {
      normalizedWarnings.add(
        'Concepto poco claro; revisa la descripción antes de guardar.',
      );
    }
    if (resolvedCategory == null) {
      normalizedWarnings.add(
        'No se pudo clasificar la categoría con certeza.',
      );
    }

    final fuelText =
        '${resolvedConcept.toLowerCase()} ${merchant?.toLowerCase() ?? ''} ${(station ?? '').toLowerCase()}';
    final isFuel = (resolvedCategory == ExpenseCategory.combustible ||
            resolvedCategory == ExpenseCategory.transporte) &&
        _containsAny(fuelText, [
          'gasolina',
          'combustible',
          'diesel',
          'gasoil',
          'repostaje',
        ]);
    if (isFuel) {
      resolvedCategory = ExpenseCategory.combustible;
      finalConcept = _normalizeFuelConcept(resolvedConcept, map);
      normalizedWarnings.add(
        'Combustible: deducibilidad aplicada por defecto al 50%; revisa antes de guardar.',
      );
    }

    final confidence = normalizedWarnings.isNotEmpty && extractedConfidence >= 1
        ? 0.9
        : extractedConfidence.toDouble();

    return ExpenseExtractionResult(
      concepto: finalConcept,
      proveedor: merchant,
      estacion: station,
      numeroFactura: invoiceNumber,
      fecha: date,
      fechaOperacion: operationDate,
      importeBase: base ?? _deriveBase(total, tax, vatRate),
      importeIva: tax,
      ivaRate: vatRate,
      importeTotal: total,
      descuento: discount,
      litros: liters,
      precioPorLitro: pricePerLiter,
      matriculaVehiculo: vehiclePlate,
      esDeducible: isFuel ? true : null,
      porcentajeDeduccion: isFuel ? 50 : null,
      categoria: resolvedCategory,
      notas: notes,
      confidence: confidence,
      warnings: normalizedWarnings,
    );
  }

  String _normalizeFuelConcept(String concept, Map<String, dynamic> map) {
    final raw = concept.trim();
    final productRaw = _readString(map['product']) ?? raw;
    final product = productRaw.toLowerCase();
    if (product.contains('efitec 98')) return 'Gasolina efitec 98';
    if (_containsAny(product, ['diesel', 'diésel', 'gasoil'])) {
      return 'Diésel ${_cleanFuelProduct(productRaw)}'.trim();
    }
    if (_containsAny(product, ['95', '98', 'gasolina', 'efitec'])) {
      return 'Gasolina ${_cleanFuelProduct(productRaw)}'.trim();
    }
    return 'Gasolina ${_cleanFuelProduct(raw)}'.trim();
  }

  String? _normalizeStation(String? station, String? merchant) {
    if (station == null || station.trim().isEmpty) return null;
    if (merchant != null && station.trim() == merchant.trim()) return null;
    return station.trim();
  }

  String _cleanFuelProduct(String value) {
    final cleaned = value
        .replaceAll(RegExp('suministro de', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'combustible' : cleaned;
  }

  double? _deriveBase(double? total, double? tax, double? vatRate) {
    if (total == null) return null;
    if (tax != null) return total - tax;
    if (vatRate != null && vatRate > 0) return total / (1 + (vatRate / 100));
    return null;
  }

  DateTime? _readDate(dynamic value) {
    final s = _readString(value);
    if (s == null) return null;
    try {
      return _parseDate(s) ?? DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  _DetectedDates _detectSpanishDates(String sourceText) {
    final fecha = _firstLabeledDate(
      sourceText,
      RegExp(
        r'(?:^|\n|\s)fecha\s*:?\s*(\d{1,2}[\/.-]\d{1,2}[\/.-]\d{4})',
        caseSensitive: false,
      ),
    );
    final operation = _firstLabeledDate(
      sourceText,
      RegExp(
        r'f\.?\s*operaci[oó]n\s*:?\s*(\d{1,2}[\/.-]\d{1,2}[\/.-]\d{4})',
        caseSensitive: false,
      ),
    );
    return _DetectedDates(date: fecha, operationDate: operation);
  }

  DateTime? _firstLabeledDate(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    if (match == null) return null;
    return _parseDate(match.group(1));
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$')
        .firstMatch(raw.trim());
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  String? _readString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  List<String> _readWarnings(dynamic value) {
    if (value is! List) return [];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  ExpenseCategory? _toCategory(String? raw) {
    if (raw == null) return null;
    final normalized = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();
    for (final c in ExpenseCategory.values) {
      if (c.name == normalized) return c;
    }
    if (_containsAny(normalized, [
      'combustible',
      'gasolina',
      'diesel',
      'gasoil',
      'repostaje',
    ])) {
      return ExpenseCategory.combustible;
    }
    if (_containsAny(normalized, [
      'transporte',
      'movilidad',
      'parking',
      'peaje',
      'taxi',
      'uber',
      'cabify',
      'renfe',
    ])) {
      return ExpenseCategory.transporte;
    }
    if (_containsAny(normalized, [
      'equipo',
      'hardware',
      'material',
      'sonido',
      'dj',
      'microfono',
      'altavoz',
      'mesa',
      'controladora',
      'cable',
    ])) {
      return ExpenseCategory.equipo;
    }
    if (_containsAny(normalized, [
      'software',
      'suscripcion',
      'saas',
      'hosting',
      'dominio',
      'licencia',
      'app',
    ])) {
      return ExpenseCategory.software;
    }
    if (_containsAny(normalized, [
      'dieta',
      'dietas',
      'comida',
      'restaurante',
      'manutencion',
    ])) {
      return ExpenseCategory.dietas;
    }
    if (_containsAny(normalized, [
      'publicidad',
      'marketing',
      'anuncio',
      'ads',
      'meta ads',
      'instagram ads',
      'google ads',
    ])) {
      return ExpenseCategory.publicidad;
    }
    if (_containsAny(normalized, [
      'formacion',
      'curso',
      'masterclass',
      'training',
      'academia',
    ])) {
      return ExpenseCategory.formacion;
    }
    if (_containsAny(normalized, ['otros', 'otro'])) {
      return ExpenseCategory.otros;
    }
    return null;
  }

  ExpenseCategory? _inferCategory({
    required String concept,
    String? merchant,
  }) {
    final text = '${concept.toLowerCase()} ${merchant?.toLowerCase() ?? ''}';
    if (_containsAny(text, [
      'gasolina',
      'combustible',
      'diesel',
      'gasoil',
      'repostaje',
    ])) {
      return ExpenseCategory.combustible;
    }
    if (_containsAny(text, [
      'uber',
      'cabify',
      'taxi',
      'renfe',
    ])) {
      return ExpenseCategory.transporte;
    }
    if (_containsAny(text, ['software', 'suscripción', 'hosting', 'saas'])) {
      return ExpenseCategory.software;
    }
    if (_containsAny(text, ['cable', 'altavoz', 'controladora', 'micrófono'])) {
      return ExpenseCategory.equipo;
    }
    if (_containsAny(text, ['comida', 'restaurante', 'dieta'])) {
      return ExpenseCategory.dietas;
    }
    if (_containsAny(text, ['ads', 'instagram', 'meta', 'publicidad'])) {
      return ExpenseCategory.publicidad;
    }
    if (_containsAny(text, ['curso', 'formación', 'training'])) {
      return ExpenseCategory.formacion;
    }
    return null;
  }

  bool _containsAny(String source, List<String> needles) {
    for (final needle in needles) {
      if (source.contains(needle)) return true;
    }
    return false;
  }

  String? _buildNotes({
    String? station,
    String? invoiceNumber,
    DateTime? operationDate,
    double? discount,
    double? liters,
    double? pricePerLiter,
    String? vehiclePlate,
  }) {
    final parts = <String>[];
    if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
      parts.add('Factura: $invoiceNumber');
    }
    if (station != null && station.isNotEmpty) parts.add('Estación: $station');
    if (operationDate != null) {
      parts.add(
        'F. Operación: ${operationDate.year.toString().padLeft(4, '0')}-'
        '${operationDate.month.toString().padLeft(2, '0')}-'
        '${operationDate.day.toString().padLeft(2, '0')}',
      );
    }
    if (vehiclePlate != null && vehiclePlate.isNotEmpty) {
      parts.add('Matrícula: $vehiclePlate');
    }
    if (liters != null) parts.add('Litros: ${liters.toStringAsFixed(3)}');
    if (pricePerLiter != null) {
      parts.add('Precio/L: ${pricePerLiter.toStringAsFixed(3)} €');
    }
    if (discount != null) {
      parts.add('Descuento: ${discount.toStringAsFixed(2)} €');
    }
    if (parts.isEmpty) return null;
    return parts.join(' | ');
  }
}

class _DetectedDates {
  final DateTime? date;
  final DateTime? operationDate;

  const _DetectedDates({
    this.date,
    this.operationDate,
  });
}
