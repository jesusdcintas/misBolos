import '../../models/invoice.dart';

/// Día (sin hora) de una fecha, en UTC.
///
/// La cuenta de días se hace en UTC a propósito: con fechas locales, el cambio
/// de hora de marzo y de octubre mete un día de 23 o 25 horas e `inDays` se
/// come un día.
DateTime _dia(DateTime fecha) => DateTime.utc(fecha.year, fecha.month, fecha.day);

/// Facturas emitidas y pendientes de cobro, de la más antigua a la más nueva.
///
/// Solo entran las que ya han llegado a su fecha de emisión: una factura con
/// fecha futura todavía no está pendiente de cobro.
List<Invoice> facturasPendientesDeCobro(
  List<Invoice> invoices, {
  DateTime? hoy,
}) {
  final referencia = _dia(hoy ?? DateTime.now());
  final pendientes = invoices
      .where(
        (i) =>
            i.status == InvoiceStatus.enviada &&
            !_dia(i.fecha).isAfter(referencia),
      )
      .toList();
  pendientes.sort((a, b) => a.fecha.compareTo(b.fecha));
  return pendientes;
}

/// Suma de los totales de [invoices].
double totalPendienteDeCobro(List<Invoice> invoices) =>
    invoices.fold<double>(0, (suma, i) => suma + i.total);

/// Días transcurridos desde la fecha de emisión. Nunca negativo.
int diasDesdeEmision(DateTime fecha, {DateTime? hoy}) {
  final dias = _dia(hoy ?? DateTime.now()).difference(_dia(fecha)).inDays;
  return dias > 0 ? dias : 0;
}
