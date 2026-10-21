/// Estimación fiscal orientativa de un periodo.
///
/// Todos los importes son BRUTOS: nunca se restan gastos ni inversiones de los
/// impuestos. Es una estimación orientativa, no un cálculo fiscal real (la
/// gestoría aplicará las deducciones correspondientes).
class FinancialSummary {
  final DateTime from;
  final DateTime to;

  /// Base imponible facturada oficialmente en el periodo (informativo).
  final double ingresosOficiales;

  /// Ingresos no facturados estimados desde bolos cobrados (informativo).
  final double ingresosB;

  /// IVA repercutido bruto de las facturas emitidas en el periodo.
  final double ivaRepercutidoBruto;

  /// IRPF teórico del pago fraccionado sobre la base imponible del periodo.
  final double irpfTeorico;

  /// IRPF ya retenido por los clientes en las facturas del periodo.
  final double irpfRetenido;

  /// IRPF a ingresar: teórico menos retenido, nunca negativo.
  final double irpfAIngresar;

  const FinancialSummary({
    required this.from,
    required this.to,
    this.ingresosOficiales = 0,
    this.ingresosB = 0,
    this.ivaRepercutidoBruto = 0,
    this.irpfTeorico = 0,
    this.irpfRetenido = 0,
    this.irpfAIngresar = 0,
  });

  /// Total IRPF del periodo: retenido + a ingresar.
  double get irpfTotal => irpfRetenido + irpfAIngresar;

  /// Los clientes han retenido más IRPF del que corresponde al periodo.
  bool get retencionSuperaIrpf => irpfRetenido > irpfTeorico;

  FinancialSummary copyWith({
    DateTime? from,
    DateTime? to,
    double? ingresosOficiales,
    double? ingresosB,
    double? ivaRepercutidoBruto,
    double? irpfTeorico,
    double? irpfRetenido,
    double? irpfAIngresar,
  }) {
    return FinancialSummary(
      from: from ?? this.from,
      to: to ?? this.to,
      ingresosOficiales: ingresosOficiales ?? this.ingresosOficiales,
      ingresosB: ingresosB ?? this.ingresosB,
      ivaRepercutidoBruto: ivaRepercutidoBruto ?? this.ivaRepercutidoBruto,
      irpfTeorico: irpfTeorico ?? this.irpfTeorico,
      irpfRetenido: irpfRetenido ?? this.irpfRetenido,
      irpfAIngresar: irpfAIngresar ?? this.irpfAIngresar,
    );
  }
}
