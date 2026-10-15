/// Estimación fiscal orientativa de un periodo.
///
/// Todos los importes son BRUTOS: nunca se restan gastos ni inversiones de los
/// impuestos. [irpfEstimadoAPagar] es una estimación orientativa, no un cálculo
/// fiscal real (la gestoría aplicará las deducciones correspondientes).
class FinancialSummary {
  final DateTime from;
  final DateTime to;

  /// Base imponible facturada oficialmente en el periodo (informativo).
  final double ingresosOficiales;

  /// Ingresos no facturados estimados desde bolos cobrados (informativo).
  final double ingresosB;

  /// Suma de gastos e inversiones del periodo (informativo, nunca se resta).
  final double totalGastosInversiones;

  /// IVA repercutido bruto de las facturas emitidas en el periodo.
  final double ivaRepercutidoBruto;

  /// IRPF ya retenido por los clientes en las facturas del periodo.
  final double irpfAdelantado;

  /// IVA estimado a pagar: igual al IVA repercutido bruto, sin restar nada.
  final double ivaEstimadoAPagar;

  /// IRPF estimado a pagar: IRPF teórico bruto sobre ingresos menos el IRPF
  /// ya adelantado por los clientes. Sin restar gastos ni inversiones.
  final double irpfEstimadoAPagar;

  const FinancialSummary({
    required this.from,
    required this.to,
    this.ingresosOficiales = 0,
    this.ingresosB = 0,
    this.totalGastosInversiones = 0,
    this.ivaRepercutidoBruto = 0,
    this.irpfAdelantado = 0,
    this.ivaEstimadoAPagar = 0,
    this.irpfEstimadoAPagar = 0,
  });

  FinancialSummary copyWith({
    DateTime? from,
    DateTime? to,
    double? ingresosOficiales,
    double? ingresosB,
    double? totalGastosInversiones,
    double? ivaRepercutidoBruto,
    double? irpfAdelantado,
    double? ivaEstimadoAPagar,
    double? irpfEstimadoAPagar,
  }) {
    return FinancialSummary(
      from: from ?? this.from,
      to: to ?? this.to,
      ingresosOficiales: ingresosOficiales ?? this.ingresosOficiales,
      ingresosB: ingresosB ?? this.ingresosB,
      totalGastosInversiones:
          totalGastosInversiones ?? this.totalGastosInversiones,
      ivaRepercutidoBruto: ivaRepercutidoBruto ?? this.ivaRepercutidoBruto,
      irpfAdelantado: irpfAdelantado ?? this.irpfAdelantado,
      ivaEstimadoAPagar: ivaEstimadoAPagar ?? this.ivaEstimadoAPagar,
      irpfEstimadoAPagar: irpfEstimadoAPagar ?? this.irpfEstimadoAPagar,
    );
  }
}
