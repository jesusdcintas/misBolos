/// Importes derivados que se muestran en Inicio.
///
/// Solo combinan cifras que ya calculan `PeriodDashboardStats` y
/// `FinancialSummary`: aquí no hay lógica fiscal ni de ingresos nueva.

/// Tramo de ingresos confirmado pero todavía sin facturar.
///
/// Es lo que queda del total previsto al quitar lo cobrado y lo pendiente de
/// cobro. Nunca es negativo: si los importes no cuadran, devuelve 0.
double confirmadoSinFacturar({
  required double totalPrevisto,
  required double cobrado,
  required double pendiente,
}) {
  final resto = totalPrevisto - cobrado - pendiente;
  return resto > 0 ? resto : 0;
}

/// Dinero que conviene reservar para Hacienda en el periodo.
///
/// El IVA repercutido se ingresa entero y del IRPF solo lo que falta por
/// ingresar, porque lo retenido por los clientes ya está en Hacienda.
double reservaParaHacienda({
  required double ivaRepercutido,
  required double irpfAIngresar,
}) {
  final total = ivaRepercutido + irpfAIngresar;
  return total > 0 ? total : 0;
}
