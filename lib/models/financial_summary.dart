class FinancialSummary {
  final DateTime from;
  final DateTime to;
  final double ingresosFacturados;
  final double ingresosHistoricosEstimados;
  final double ivaRepercutidoFacturas;
  final double ivaRepercutidoHistoricoEstimado;
  final double gastosDeducibles;
  final double ivaSoportadoGastos;
  final double ivaSoportadoInversiones;
  final double amortizacion;
  final List<FinancialQuarterSummary> quarters;

  const FinancialSummary({
    required this.from,
    required this.to,
    this.ingresosFacturados = 0,
    this.ingresosHistoricosEstimados = 0,
    this.ivaRepercutidoFacturas = 0,
    this.ivaRepercutidoHistoricoEstimado = 0,
    this.gastosDeducibles = 0,
    this.ivaSoportadoGastos = 0,
    this.ivaSoportadoInversiones = 0,
    this.amortizacion = 0,
    this.quarters = const [],
  });

  double get ingresosOficiales =>
      ingresosFacturados + ingresosHistoricosEstimados;

  double get ivaRepercutido =>
      ivaRepercutidoFacturas + ivaRepercutidoHistoricoEstimado;

  double get ivaSoportado => ivaSoportadoGastos + ivaSoportadoInversiones;

  double get ivaAPagar => ivaRepercutido - ivaSoportado;

  double get beneficioEstimado =>
      ingresosOficiales - gastosDeducibles - amortizacion;

  bool get hasEstimatedHistoricalData =>
      ingresosHistoricosEstimados > 0 || ivaRepercutidoHistoricoEstimado > 0;
}

class FinancialQuarterSummary {
  final int year;
  final int quarter;
  final double ingresosFacturados;
  final double ingresosHistoricosEstimados;
  final double ivaRepercutidoFacturas;
  final double ivaRepercutidoHistoricoEstimado;
  final double gastosDeducibles;
  final double ivaSoportadoGastos;
  final double ivaSoportadoInversiones;
  final double amortizacion;

  const FinancialQuarterSummary({
    required this.year,
    required this.quarter,
    this.ingresosFacturados = 0,
    this.ingresosHistoricosEstimados = 0,
    this.ivaRepercutidoFacturas = 0,
    this.ivaRepercutidoHistoricoEstimado = 0,
    this.gastosDeducibles = 0,
    this.ivaSoportadoGastos = 0,
    this.ivaSoportadoInversiones = 0,
    this.amortizacion = 0,
  });

  double get ingresosOficiales =>
      ingresosFacturados + ingresosHistoricosEstimados;

  double get ivaRepercutido =>
      ivaRepercutidoFacturas + ivaRepercutidoHistoricoEstimado;

  double get ivaSoportado => ivaSoportadoGastos + ivaSoportadoInversiones;

  double get ivaAPagar => ivaRepercutido - ivaSoportado;

  double get beneficioEstimado =>
      ingresosOficiales - gastosDeducibles - amortizacion;
}
