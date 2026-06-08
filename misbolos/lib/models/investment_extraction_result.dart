import 'asset.dart';

class InvestmentExtractionResult {
  final String? name;
  final String? supplier;
  final String? invoiceNumber;
  final DateTime? purchaseDate;
  final String? concept;
  final AssetCategory? category;
  final double? baseAmount;
  final double? taxAmount;
  final double? vatRate;
  final double? totalAmount;
  final int? usefulLifeYears;
  final double? maxAnnualPercentage;
  final double? annualAmortizationAmount;
  final double? deductiblePercentage;
  final double confidence;
  final List<String> warnings;

  const InvestmentExtractionResult({
    this.name,
    this.supplier,
    this.invoiceNumber,
    this.purchaseDate,
    this.concept,
    this.category,
    this.baseAmount,
    this.taxAmount,
    this.vatRate,
    this.totalAmount,
    this.usefulLifeYears,
    this.maxAnnualPercentage,
    this.annualAmortizationAmount,
    this.deductiblePercentage,
    this.confidence = 0,
    this.warnings = const [],
  });
}
