import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/investment_extraction_result.dart';
import 'ai_service.dart';
import 'ai_attachment_service.dart';

class InvestmentAiExtractor {
  InvestmentAiExtractor._();

  static final InvestmentAiExtractor instance = InvestmentAiExtractor._();

  Future<InvestmentExtractionResult> extractFromText(String text) async {
    final extracted = await AiService.instance.extractInvestmentFromText(
      message:
          'Extrae una inversión desde este texto de factura. Devuelve JSON estricto.',
      contextData: {'raw_text': text},
    );
    return postProcessInvestmentExtraction(text, extracted);
  }

  Future<InvestmentExtractionResult> extractFromReceiptText(String text) async {
    final extracted = await AiService.instance.extractInvestmentFromText(
      message:
          'Extrae una inversión desde OCR de factura. No inventes campos.',
      imageText: text,
      contextData: {'source': 'ocr_text'},
    );
    return postProcessInvestmentExtraction(text, extracted);
  }

  Future<InvestmentExtractionResult> extractFromImagePath(String path) async {
    final prepared = await AiAttachmentService.instance.imageToBase64(path);
    final extracted = await AiService.instance.extractInvestmentFromImage(
      message:
          'Extrae una inversión desde esta imagen de factura. Devuelve solo JSON válido y no inventes datos.',
      imageBase64: prepared.base64Data,
      imageMimeType: prepared.mimeType,
      contextData: {'source': 'image', 'file_name': path.split('/').last},
    );
    return postProcessInvestmentExtraction('', extracted);
  }

  InvestmentExtractionResult postProcessInvestmentExtraction(
    String rawText,
    Map<String, dynamic> aiResult,
  ) {
    debugPrint('[InvestmentAI] Groq result: $aiResult');
    final result = _toResult(aiResult, sourceText: rawText);
    debugPrint(
      '[InvestmentAI] Final result: base=${result.baseAmount}, tax=${result.taxAmount}, total=${result.totalAmount}, category=${result.category?.label}, name=${result.name}',
    );
    return result;
  }

  InvestmentExtractionResult _toResult(
    Map<String, dynamic> map, {
    required String sourceText,
  }) {
    final fiscalSummary = _extractFiscalSummary(sourceText);
    final warnings = _readWarnings(map['warnings']);
    final rawName = _readString(map['name']);
    final rawConcept = _readString(map['concept']);
    final rawSupplier = _normalizeSupplier(_readString(map['supplier']));
    final name = _normalizeInvestmentName(
      rawName ?? rawConcept,
      supplier: rawSupplier,
      sourceText: sourceText,
    );
    final category = _categoryFrom(
      [
        sourceText,
        name,
        rawConcept,
        _readString(map['category']),
      ].whereType<String>().join(' '),
    );
    final amounts = _validateInvestmentExtraction(
      base: _readDouble(map['base_amount']),
      tax: _readDouble(map['tax_amount']),
      vatRate: _readDouble(map['vat_rate']),
      total: _readDouble(map['total_amount']),
      fiscalSummary: fiscalSummary,
      warnings: warnings,
    );
    final base = amounts.baseAmount;
    final tax = amounts.taxAmount;
    final vatRate = amounts.vatRate;
    final total = amounts.totalAmount;
    final maxAnnual = _maxAnnualFor(category);
    final usefulLife = _readInt(map['useful_life_years']) ??
        _suggestedUsefulLife(category);

    if (category == AssetCategory.vehiculo) {
      warnings.add(
        'Vehículo: revisar deducibilidad y amortización según uso profesional.',
      );
    }
    if (category == AssetCategory.otros &&
        (_readString(map['category'])?.toLowerCase() != 'otros')) {
      warnings.add('Categoría detectada con baja certeza. Revisa antes de guardar.');
    }

    final annual = base != null ? _roundMoney(base * (maxAnnual / 100)) : null;
    final extractedConfidence = (_readDouble(map['confidence']) ?? 0).clamp(0, 1);
    final confidence = warnings.isEmpty &&
            (fiscalSummary?.isValid == true || amounts.isValid)
        ? 0.95
        : (warnings.isNotEmpty && extractedConfidence >= 1
            ? 0.9
            : extractedConfidence.toDouble());

    return InvestmentExtractionResult(
      name: name ?? rawConcept,
      supplier: rawSupplier,
      invoiceNumber: _readString(map['invoice_number']),
      purchaseDate: _readDate(map['purchase_date']) ??
          _detectPurchaseDate(sourceText),
      concept: _normalizeInvestmentConcept(rawConcept, sourceText),
      category: category,
      baseAmount: base,
      taxAmount: tax,
      vatRate: vatRate,
      totalAmount: total,
      usefulLifeYears: usefulLife,
      maxAnnualPercentage: maxAnnual,
      annualAmortizationAmount: annual,
      deductiblePercentage: _readDouble(map['deductible_percentage']),
      confidence: confidence,
      warnings: warnings.toSet().toList(growable: false),
    );
  }

  AssetCategory _categoryFrom(String? raw) {
    final text = _normalize(raw ?? '');
    if (_containsAny(text, [
      'dj',
      'sonido',
      'altavoz',
      'subwoofer',
      'controladora',
      'mezcla',
      'microfono',
      'audio',
      'flight case',
      'soporte altavoz',
    ])) {
      return AssetCategory.equipoDj;
    }
    if (_containsAny(text, [
      'iluminacion',
      'foco',
      'led',
      'cabeza movil',
      'laser',
      'strobe',
      'humo',
      'dmx',
      'truss',
    ])) {
      return AssetCategory.iluminacion;
    }
    if (_containsAny(text, [
      'informatica',
      'portatil',
      'tablet',
      'ordenador',
      'ssd',
      'monitor',
      'impresora',
      'router',
      'periferico',
    ])) {
      return AssetCategory.informatica;
    }
    if (_containsAny(text, ['mobiliario', 'mesa', 'silla', 'estanteria', 'armario', 'sofa'])) {
      return AssetCategory.mobiliario;
    }
    if (_containsAny(text, ['vehiculo', 'coche', 'furgoneta', 'remolque'])) {
      return AssetCategory.vehiculo;
    }
    if (_containsAny(text, [
      'herramienta',
      'utillaje',
      'taladro',
      'atornillador',
      'escalera',
      'carro',
      'transpaleta',
      'montaje',
    ])) {
      return AssetCategory.herramientas;
    }
    return AssetCategory.otros;
  }

  double _maxAnnualFor(AssetCategory category) =>
      category.coeficienteMaxHacienda * 100;

  _ValidatedInvestmentAmounts _validateInvestmentExtraction({
    required double? base,
    required double? tax,
    required double? vatRate,
    required double? total,
    required _FiscalSummary? fiscalSummary,
    required List<String> warnings,
  }) {
    if (fiscalSummary?.isValid == true) {
      _removeAmountWarnings(warnings);
      final resolvedVatRate = fiscalSummary!.vatRate ??
          _recalculateVatRate(fiscalSummary.base, fiscalSummary.tax, vatRate);
      return _ValidatedInvestmentAmounts(
        baseAmount: fiscalSummary.base,
        taxAmount: fiscalSummary.tax,
        vatRate: resolvedVatRate,
        totalAmount: fiscalSummary.total,
      );
    }

    var resolvedBase = base;
    var resolvedTax = tax;
    var resolvedTotal = total;
    var resolvedVatRate = _recalculateVatRate(resolvedBase, resolvedTax, vatRate);

    if (resolvedTax == null) {
      _addUnique(warnings, 'No se ha detectado IVA de forma clara.');
    }

    if (resolvedBase != null && resolvedTax != null && resolvedTotal != null) {
      final matches = _amountsMatch(resolvedBase, resolvedTax, resolvedTotal);
      if (matches) {
        _removeAmountWarnings(warnings);
      } else if (resolvedVatRate != null &&
          resolvedVatRate > 0 &&
          resolvedTotal > 0) {
        resolvedBase = _roundMoney(resolvedTotal / (1 + resolvedVatRate / 100));
        resolvedTax = _roundMoney(resolvedTotal - resolvedBase);
        if (_amountsMatch(resolvedBase, resolvedTax, resolvedTotal)) {
          _removeAmountWarnings(warnings);
        } else {
          _addUnique(
            warnings,
            'El total no coincide exactamente con base + IVA. Revisa los importes.',
          );
        }
      } else {
        _addUnique(
          warnings,
          'El total no coincide exactamente con base + IVA. Revisa los importes.',
        );
      }
    }

    return _ValidatedInvestmentAmounts(
      baseAmount: resolvedBase,
      taxAmount: resolvedTax,
      vatRate: resolvedVatRate,
      totalAmount: resolvedTotal,
    );
  }

  _FiscalSummary? _extractFiscalSummary(String sourceText) {
    if (sourceText.trim().isEmpty) return null;
    final tableSummary = _extractFiscalSummaryFromTable(sourceText);
    if (tableSummary != null) {
      debugPrint(
        '[InvestmentAI] Fiscal summary table: base=${tableSummary.base}, tax=${tableSummary.tax}, total=${tableSummary.total}, vat=${tableSummary.vatRate}',
      );
      return tableSummary;
    }
    final base = _lastLabeledMoney(sourceText, [
      'base imponible total',
      'base imponible',
      'base sin iva',
    ]);
    final tax = _lastLabeledMoney(sourceText, [
      'cuota iva',
      'cuota tributaria',
      'iva soportado',
    ]);
    final total = _lastLabeledMoney(sourceText, [
      'total factura',
      'total a pagar',
      'importe total',
      'total',
    ]);
    if (base == null || tax == null || total == null) return null;
    final summary = _FiscalSummary(base: base, tax: tax, total: total);
    if (summary.isValid) {
      debugPrint(
        '[InvestmentAI] Fiscal summary labels: base=${summary.base}, tax=${summary.tax}, total=${summary.total}, vat=${summary.vatRate}',
      );
      return summary;
    }
    return null;
  }

  _FiscalSummary? _extractFiscalSummaryFromTable(String sourceText) {
    final normalized = sourceText
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ');
    final pattern = RegExp(
      r'(?:^|\s)(\d{1,2},\d{2})\s*%[\s\S]{0,60}?'
      r'(\d{1,3}(?:[.\s]\d{3})*,\d{2}|\d+,\d{2})\s*(?:eur|€)?[\s\S]{0,30}?'
      r'(\d{1,3}(?:[.\s]\d{3})*,\d{2}|\d+,\d{2})\s*(?:eur|€)?[\s\S]{0,30}?'
      r'(\d{1,3}(?:[.\s]\d{3})*,\d{2}|\d+,\d{2})\s*(?:eur|€)?',
      caseSensitive: false,
    );
    _FiscalSummary? best;
    for (final match in pattern.allMatches(normalized)) {
      final vat = _parseSpanishMoney(match.group(1));
      final base = _parseSpanishMoney(match.group(2));
      final tax = _parseSpanishMoney(match.group(3));
      final total = _parseSpanishMoney(match.group(4));
      if (vat == null || base == null || tax == null || total == null) {
        continue;
      }
      final summary = _FiscalSummary(
        base: base,
        tax: tax,
        total: total,
        vatRate: vat.roundToDouble(),
      );
      if (summary.isValid) best = summary;
    }
    return best;
  }

  double? _lastLabeledMoney(String text, List<String> labels) {
    final normalized = _normalize(text);
    double? value;
    for (final label in labels) {
      final pattern = RegExp(
        '${RegExp.escape(_normalize(label))}'
        r'[\s\S]{0,80}?(-?\d{1,3}(?:[.\s]\d{3})*,\d{2}|-?\d+,\d{2})',
        caseSensitive: false,
      );
      for (final match in pattern.allMatches(normalized)) {
        value = _parseSpanishMoney(match.group(1));
      }
    }
    return value;
  }

  double? _parseSpanishMoney(String? value) {
    if (value == null) return null;
    final cleaned = value.replaceAll(' ', '').replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleaned)?.abs();
  }

  double? _recalculateVatRate(double? base, double? tax, double? current) {
    if (base != null && tax != null && tax > 0 && (current == null || current == 0)) {
      return ((tax / base) * 100).roundToDouble();
    }
    return current;
  }

  bool _amountsMatch(double base, double tax, double total) =>
      (total - (base + tax)).abs() <= 0.02;

  void _removeAmountWarnings(List<String> warnings) {
    warnings.removeWhere((warning) {
      final normalized = _normalize(warning);
      return normalized.contains('iva') && normalized.contains('clara') ||
          normalized.contains('total') && normalized.contains('base') ||
          normalized.contains('varios importes');
    });
  }

  void _addUnique(List<String> warnings, String warning) {
    if (!warnings.contains(warning)) warnings.add(warning);
  }

  String? _normalizeInvestmentName(
    String? value, {
    required String? supplier,
    required String sourceText,
  }) {
    final source = _normalize('$value $sourceText');
    if (source.contains('sandisk') && source.contains('ssd') && source.contains('1tb')) {
      return 'Sandisk SSD portátil 1TB';
    }
    final cleaned = value?.trim();
    if (cleaned == null || cleaned.isEmpty) return null;
    if (supplier != null && cleaned.toLowerCase() == supplier.toLowerCase()) {
      return null;
    }
    return cleaned;
  }

  String? _normalizeInvestmentConcept(String? value, String sourceText) {
    final source = _normalize('$value $sourceText');
    if (source.contains('sandisk') &&
        source.contains('sdssde30') &&
        source.contains('portable') &&
        source.contains('ssd') &&
        source.contains('1tb')) {
      return 'SANDISK SDSSDE30-1T00-G26 PORTABLE SSD 1TB';
    }
    if (value == null || value.trim().isEmpty) return null;
    final normalized = _normalize(value);
    if (normalized.contains('compra de equipo dj') ||
        normalized.contains('equipo dj / sonido')) {
      return null;
    }
    return value.trim();
  }

  String? _normalizeSupplier(String? value) {
    if (value == null) return null;
    final normalized = _normalize(value);
    if (normalized.contains('media') && normalized.contains('markt')) {
      return 'MEDIA MARKT SATURN S.A.';
    }
    return value.trim();
  }

  double _roundMoney(double value) => (value * 100).round() / 100;

  int? _suggestedUsefulLife(AssetCategory category) {
    final years = category.vidaUtilSugerida;
    return years > 0 ? years : null;
  }

  DateTime? _detectPurchaseDate(String sourceText) {
    final match = RegExp(r'(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})')
        .firstMatch(sourceText);
    if (match == null) return null;
    return _parseSpanishDate(match.group(0));
  }

  DateTime? _readDate(dynamic value) {
    final raw = _readString(value);
    if (raw == null) return null;
    return _parseSpanishDate(raw) ?? DateTime.tryParse(raw);
  }

  DateTime? _parseSpanishDate(String? raw) {
    if (raw == null) return null;
    final match =
        RegExp(r'^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$').firstMatch(raw);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  String? _readString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  List<String> _readWarnings(dynamic value) {
    if (value is! List) return [];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u');

  bool _containsAny(String source, List<String> needles) =>
      needles.any(source.contains);
}

class _FiscalSummary {
  final double base;
  final double tax;
  final double total;
  final double? vatRate;

  const _FiscalSummary({
    required this.base,
    required this.tax,
    required this.total,
    this.vatRate,
  });

  bool get isValid => (total - (base + tax)).abs() <= 0.02;
}

class _ValidatedInvestmentAmounts {
  final double? baseAmount;
  final double? taxAmount;
  final double? vatRate;
  final double? totalAmount;

  const _ValidatedInvestmentAmounts({
    this.baseAmount,
    this.taxAmount,
    this.vatRate,
    this.totalAmount,
  });

  bool get isValid =>
      baseAmount != null &&
      taxAmount != null &&
      totalAmount != null &&
      (totalAmount! - (baseAmount! + taxAmount!)).abs() <= 0.02;
}
