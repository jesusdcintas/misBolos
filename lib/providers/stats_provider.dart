import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gig.dart';
import '../models/invoice.dart';
import 'client_provider.dart';
import 'gig_provider.dart';
import 'invoice_provider.dart';

// ==================== DASHBOARD PERIOD ====================

enum DashboardPeriodMode { mes, trimestre, anio }

const _periodMonthNames = [
  '', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

@immutable
class DashboardPeriod {
  final DashboardPeriodMode mode;
  final int year;
  final int month;   // 1-12
  final int quarter; // 1-4

  const DashboardPeriod({
    required this.mode,
    required this.year,
    required this.month,
    required this.quarter,
  });

  DashboardPeriod copyWith({DashboardPeriodMode? mode, int? year, int? month, int? quarter}) {
    return DashboardPeriod(
      mode: mode ?? this.mode,
      year: year ?? this.year,
      month: month ?? this.month,
      quarter: quarter ?? this.quarter,
    );
  }

  String get label {
    switch (mode) {
      case DashboardPeriodMode.mes:
        return '${_periodMonthNames[month]} $year';
      case DashboardPeriodMode.trimestre:
        return 'T$quarter $year';
      case DashboardPeriodMode.anio:
        return '$year';
    }
  }

  String get prevLabel {
    final p = previous;
    return p.label;
  }

  DashboardPeriod get previous {
    switch (mode) {
      case DashboardPeriodMode.mes:
        if (month == 1) return copyWith(year: year - 1, month: 12);
        return copyWith(month: month - 1);
      case DashboardPeriodMode.trimestre:
        if (quarter == 1) return copyWith(year: year - 1, quarter: 4);
        return copyWith(quarter: quarter - 1);
      case DashboardPeriodMode.anio:
        return copyWith(year: year - 1);
    }
  }

  DashboardPeriod get next {
    switch (mode) {
      case DashboardPeriodMode.mes:
        if (month == 12) return copyWith(year: year + 1, month: 1);
        return copyWith(month: month + 1);
      case DashboardPeriodMode.trimestre:
        if (quarter == 4) return copyWith(year: year + 1, quarter: 1);
        return copyWith(quarter: quarter + 1);
      case DashboardPeriodMode.anio:
        return copyWith(year: year + 1);
    }
  }

  bool get isFuture {
    final now = DateTime.now();
    switch (mode) {
      case DashboardPeriodMode.mes:
        return year > now.year || (year == now.year && month > now.month);
      case DashboardPeriodMode.trimestre:
        final currentQ = ((now.month - 1) ~/ 3) + 1;
        return year > now.year || (year == now.year && quarter > currentQ);
      case DashboardPeriodMode.anio:
        return year > now.year;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardPeriod &&
          mode == other.mode &&
          year == other.year &&
          month == other.month &&
          quarter == other.quarter;

  @override
  int get hashCode => Object.hash(mode, year, month, quarter);
}

final dashboardPeriodProvider = StateProvider<DashboardPeriod>((ref) {
  final now = DateTime.now();
  return DashboardPeriod(
    mode: DashboardPeriodMode.mes,
    year: now.year,
    month: now.month,
    quarter: ((now.month - 1) ~/ 3) + 1,
  );
});

// ==================== PERIOD-BASED DASHBOARD STATS ====================

class PeriodDashboardStats {
  final double cobradoOficial;
  final double pendienteOficial;
  final double cobradoEnB;
  final double pendienteEnB;
  final int facturasEnviadasSinCobrar;
  final int totalBolos;
  final int numBolosB;
  final double ivaAcumulado;
  final double estimado;
  // Previous period (for comparison)
  final double? prevCobradoOficial;
  final double? prevTotalCobrado;
  final String? prevLabel;

  PeriodDashboardStats({
    this.cobradoOficial = 0,
    this.pendienteOficial = 0,
    this.cobradoEnB = 0,
    this.pendienteEnB = 0,
    this.facturasEnviadasSinCobrar = 0,
    this.totalBolos = 0,
    this.numBolosB = 0,
    this.ivaAcumulado = 0,
    this.estimado = 0,
    this.prevCobradoOficial,
    this.prevTotalCobrado,
    this.prevLabel,
  });

  double get totalCobrado => cobradoOficial + cobradoEnB;
}

/// Returns (startDate, endDate) for the given period
(DateTime, DateTime) _periodRange(DashboardPeriod period) {
  switch (period.mode) {
    case DashboardPeriodMode.mes:
      final start = DateTime(period.year, period.month, 1);
      final end = DateTime(period.year, period.month + 1, 0);
      return (start, end);
    case DashboardPeriodMode.trimestre:
      final startM = (period.quarter - 1) * 3 + 1;
      final start = DateTime(period.year, startM, 1);
      final end = DateTime(period.year, startM + 3, 0);
      return (start, end);
    case DashboardPeriodMode.anio:
      return (DateTime(period.year, 1, 1), DateTime(period.year, 12, 31));
  }
}

PeriodDashboardStats _calcPeriodStats(
  DashboardPeriod period,
  List<Gig> allGigs,
  List<Invoice> allInvoices,
) {
  final (start, end) = _periodRange(period);

  final gigsInPeriod = allGigs.where((g) =>
    !g.fecha.isBefore(start) && !g.fecha.isAfter(end) &&
    g.status != GigStatus.cancelado
  ).toList();

  final invoicesInPeriod = allInvoices.where((i) =>
    !i.fecha.isBefore(start) && !i.fecha.isAfter(end)
  ).toList();

  double cobradoOficial = 0;
  double pendienteOficial = 0;
  int facturasEnviadas = 0;

  for (final inv in invoicesInPeriod) {
    if (inv.status == InvoiceStatus.pagada) {
      cobradoOficial += inv.total;
    } else if (inv.status == InvoiceStatus.enviada) {
      pendienteOficial += inv.total;
      facturasEnviadas++;
    }
  }

  // Bolos facturables sin factura pagada/enviada
  for (final gig in gigsInPeriod) {
    final cachet = gig.cachet ?? 0;
    if (gig.facturable &&
        (gig.status == GigStatus.pendiente || gig.status == GigStatus.facturaGenerada)) {
      pendienteOficial += cachet;
    }
  }

  double cobradoEnB = 0;
  double pendienteEnB = 0;
  int numBolosB = 0;
  for (final gig in gigsInPeriod) {
    final cachet = gig.cachet ?? 0;
    if (!gig.facturable) {
      if (gig.status == GigStatus.cobradoEnB) {
        cobradoEnB += cachet;
        numBolosB++;
      } else if (gig.status == GigStatus.pendiente) {
        pendienteEnB += cachet;
        numBolosB++;
      }
    }
  }

  // IVA acumulado (facturas pagadas)
  double iva = 0;
  for (final inv in invoicesInPeriod) {
    if (inv.status == InvoiceStatus.pagada) {
      iva += inv.ivaAmount;
    }
  }

  return PeriodDashboardStats(
    cobradoOficial: cobradoOficial,
    pendienteOficial: pendienteOficial,
    cobradoEnB: cobradoEnB,
    pendienteEnB: pendienteEnB,
    facturasEnviadasSinCobrar: facturasEnviadas,
    totalBolos: gigsInPeriod.length,
    numBolosB: numBolosB,
    ivaAcumulado: iva,
    estimado: cobradoOficial + pendienteOficial + cobradoEnB + pendienteEnB,
  );
}

final periodDashboardStatsProvider =
    FutureProvider.family<PeriodDashboardStats, DashboardPeriod>((ref, period) async {
  final allGigs = await ref.watch(gigsProvider.future);
  final allInvoices = await ref.watch(invoicesProvider.future);

  final stats = _calcPeriodStats(period, allGigs, allInvoices);

  // Previous period comparison
  final prev = period.previous;
  final prevStats = _calcPeriodStats(prev, allGigs, allInvoices);
  final hasPrev = prevStats.totalCobrado > 0 || prevStats.cobradoOficial > 0;

  return PeriodDashboardStats(
    cobradoOficial: stats.cobradoOficial,
    pendienteOficial: stats.pendienteOficial,
    cobradoEnB: stats.cobradoEnB,
    pendienteEnB: stats.pendienteEnB,
    facturasEnviadasSinCobrar: stats.facturasEnviadasSinCobrar,
    totalBolos: stats.totalBolos,
    numBolosB: stats.numBolosB,
    ivaAcumulado: stats.ivaAcumulado,
    estimado: stats.estimado,
    prevCobradoOficial: hasPrev ? prevStats.cobradoOficial : null,
    prevTotalCobrado: hasPrev ? prevStats.totalCobrado : null,
    prevLabel: hasPrev ? prev.label : null,
  );
});

// ==================== ORIGINAL DASHBOARD STATS ====================

class DashboardStats {
  final double cobradoOficialMes;
  final double pendienteOficialMes;
  final int facturasEnviadasSinCobrar;
  final double cobradoEnBMes;
  final double pendienteEnBMes;
  final int totalBolosMes;
  final double cobradoOficialMesAnterior;
  final double pendienteOficialMesAnterior;

  DashboardStats({
    this.cobradoOficialMes = 0,
    this.pendienteOficialMes = 0,
    this.facturasEnviadasSinCobrar = 0,
    this.cobradoEnBMes = 0,
    this.pendienteEnBMes = 0,
    this.totalBolosMes = 0,
    this.cobradoOficialMesAnterior = 0,
    this.pendienteOficialMesAnterior = 0,
  });
}

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final now = DateTime.now();
  final gigs = await ref.watch(
    gigsMonthProvider((year: now.year, month: now.month)).future,
  );
  final allInvoices = await ref.watch(invoicesProvider.future);
  
  // Filtrar facturas del mes actual
  final invoicesMonth = allInvoices.where((i) => 
    i.fecha.year == now.year && i.fecha.month == now.month
  ).toList();

  // Mes anterior
  final prevMonth = now.month == 1 ? 12 : now.month - 1;
  final prevYear = now.month == 1 ? now.year - 1 : now.year;
  final invoicesPrev = allInvoices.where((i) =>
    i.fecha.year == prevYear && i.fecha.month == prevMonth
  ).toList();
  final allGigs = await ref.watch(gigsProvider.future);
  final gigsPrev = allGigs.where((g) =>
    g.fecha.year == prevYear && g.fecha.month == prevMonth
  ).toList();

  double cobradoOficial = 0;
  double pendienteOficial = 0;
  int facturasEnviadas = 0;
  double cobradoEnB = 0;
  double pendienteEnB = 0;

  // Calcular ingresos oficiales desde facturas (para consistencia con resumen financiero)
  for (final inv in invoicesMonth) {
    if (inv.status == InvoiceStatus.pagada) {
      cobradoOficial += inv.total;
    } else if (inv.status == InvoiceStatus.enviada) {
      pendienteOficial += inv.total;
      facturasEnviadas++;
    }
  }
  
  // Añadir bolos facturables que aún no tienen factura pagada/enviada (pendientes de facturar)
  for (final gig in gigs) {
    final cachet = gig.cachet ?? 0;
    if (gig.facturable) {
      if (gig.status == GigStatus.facturaGenerada || gig.status == GigStatus.pendiente) {
        pendienteOficial += cachet;
      }
    } else {
      // Ingresos en B - siguen basándose en el gig
      if (gig.status == GigStatus.cobradoEnB) {
        cobradoEnB += cachet;
      } else if (gig.status == GigStatus.pendiente) {
        pendienteEnB += cachet;
      }
    }
  }

  // Mes anterior - misma lógica
  double cobradoOficialPrev = 0;
  double pendienteOficialPrev = 0;
  for (final inv in invoicesPrev) {
    if (inv.status == InvoiceStatus.pagada) {
      cobradoOficialPrev += inv.total;
    } else if (inv.status == InvoiceStatus.enviada) {
      pendienteOficialPrev += inv.total;
    }
  }
  for (final gig in gigsPrev) {
    final cachet = gig.cachet ?? 0;
    if (gig.facturable) {
      if (gig.status == GigStatus.facturaGenerada || gig.status == GigStatus.pendiente) {
        pendienteOficialPrev += cachet;
      }
    }
  }

  return DashboardStats(
    cobradoOficialMes: cobradoOficial,
    pendienteOficialMes: pendienteOficial,
    facturasEnviadasSinCobrar: facturasEnviadas,
    cobradoEnBMes: cobradoEnB,
    pendienteEnBMes: pendienteEnB,
    totalBolosMes: gigs.where((g) => g.status != GigStatus.cancelado).length,
    cobradoOficialMesAnterior: cobradoOficialPrev,
    pendienteOficialMesAnterior: pendienteOficialPrev,
  );
});

class MonthlyIncome {
  final int year;
  final int month;
  final double oficial;
  final double enB;

  MonthlyIncome({
    required this.year,
    required this.month,
    this.oficial = 0,
    this.enB = 0,
  });

  double get total => oficial + enB;
}

final yearlyStatsProvider =
    FutureProvider.family<List<MonthlyIncome>, int>((ref, year) async {
  final allGigs = await ref.watch(gigsProvider.future);
  final months = <MonthlyIncome>[];

  for (int m = 1; m <= 12; m++) {
    double oficial = 0;
    double enB = 0;

    for (final gig in allGigs) {
      if (gig.fecha.year == year && gig.fecha.month == m) {
        final cachet = gig.cachet ?? 0;
        if (gig.facturable && gig.status == GigStatus.pagado) {
          oficial += cachet;
        } else if (!gig.facturable && gig.status == GigStatus.cobradoEnB) {
          enB += cachet;
        }
      }
    }

    months.add(MonthlyIncome(year: year, month: m, oficial: oficial, enB: enB));
  }

  return months;
});

final ivaAcumuladoProvider = FutureProvider.family<double, int>((ref, year) async {
  final invoices = await ref.watch(invoicesProvider.future);
  double total = 0;
  for (final inv in invoices) {
    if (inv.fecha.year == year && inv.status == InvoiceStatus.pagada) {
      total += inv.ivaAmount;
    }
  }
  return total;
});

// ==================== QUARTERLY INCOME (para gráfico trimestral) ====================

class QuarterlyIncome {
  final int quarter; // 1-4
  final int year;
  final double oficial;
  final double enB;

  QuarterlyIncome({
    required this.quarter,
    required this.year,
    this.oficial = 0,
    this.enB = 0,
  });

  double get total => oficial + enB;
}

final quarterlyIncomeProvider =
    FutureProvider.family<List<QuarterlyIncome>, int>((ref, year) async {
  final months = await ref.watch(yearlyStatsProvider(year).future);
  final quarters = <QuarterlyIncome>[];

  for (int q = 1; q <= 4; q++) {
    double oficial = 0;
    double enB = 0;
    final startM = (q - 1) * 3 + 1;
    final endM = q * 3;
    for (final m in months) {
      if (m.month >= startM && m.month <= endM) {
        oficial += m.oficial;
        enB += m.enB;
      }
    }
    quarters.add(QuarterlyIncome(quarter: q, year: year, oficial: oficial, enB: enB));
  }

  return quarters;
});

// ==================== IVA POR TRIMESTRE DETALLADO ====================

class QuarterVatInvoice {
  final String invoiceId;
  final int numero;
  final String clientName;
  final DateTime fecha;
  final double base;
  final double iva;

  QuarterVatInvoice({
    required this.invoiceId,
    required this.numero,
    required this.clientName,
    required this.fecha,
    required this.base,
    required this.iva,
  });
}

class QuarterVatDetail {
  final int quarter;
  final int year;
  final double ivaTotal;
  final DateTime declarationDate;
  final int daysRemaining;
  final String status; // 'pendiente_declarar', 'en_curso', 'proximo', 'vencido'
  final List<QuarterVatInvoice> invoices;

  QuarterVatDetail({
    required this.quarter,
    required this.year,
    required this.ivaTotal,
    required this.declarationDate,
    required this.daysRemaining,
    required this.status,
    required this.invoices,
  });
}

DateTime _declarationDate(int quarter, int year) {
  switch (quarter) {
    case 1: return DateTime(year, 4, 20);
    case 2: return DateTime(year, 7, 20);
    case 3: return DateTime(year, 10, 20);
    case 4: return DateTime(year + 1, 1, 30);
    default: return DateTime(year, 4, 20);
  }
}

final yearlyVatDetailProvider =
    FutureProvider.family<List<QuarterVatDetail>, int>((ref, year) async {
  final allInvoices = await ref.watch(invoicesProvider.future);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final currentQuarter = ((now.month - 1) ~/ 3) + 1;

  final result = <QuarterVatDetail>[];

  for (int q = 1; q <= 4; q++) {
    final startM = (q - 1) * 3 + 1;
    final endM = q * 3;

    final qInvoices = allInvoices.where((inv) =>
      inv.fecha.year == year &&
      inv.fecha.month >= startM &&
      inv.fecha.month <= endM &&
      inv.status == InvoiceStatus.pagada
    ).toList();

    double ivaTotal = 0;
    final invoiceDetails = <QuarterVatInvoice>[];
    for (final inv in qInvoices) {
      ivaTotal += inv.ivaAmount;
      final client = await ref.read(clientByIdProvider(inv.clientId).future);
      invoiceDetails.add(QuarterVatInvoice(
        invoiceId: inv.id,
        numero: inv.numero,
        clientName: client?.nombre ?? 'Cliente desconocido',
        fecha: inv.fecha,
        base: inv.subtotal,
        iva: inv.ivaAmount,
      ));
    }

    final declDate = _declarationDate(q, year);
    final daysLeft = declDate.difference(today).inDays;

    String status;
    if (year < now.year || (year == now.year && q < currentQuarter)) {
      status = daysLeft < 0 && ivaTotal > 0 ? 'pendiente_declarar' : 'pasado';
    } else if (year == now.year && q == currentQuarter) {
      status = 'en_curso';
    } else {
      status = 'proximo';
    }

    result.add(QuarterVatDetail(
      quarter: q,
      year: year,
      ivaTotal: ivaTotal,
      declarationDate: declDate,
      daysRemaining: daysLeft,
      status: status,
      invoices: invoiceDetails,
    ));
  }

  return result;
});

// ==================== TOOLTIP DATA (mes o trimestre pulsado) ====================

class PeriodTooltipData {
  final String label;
  final double totalCobrado;
  final double totalIva;
  final int numFacturas;

  PeriodTooltipData({
    required this.label,
    required this.totalCobrado,
    required this.totalIva,
    required this.numFacturas,
  });
}

final monthTooltipProvider =
    FutureProvider.family<PeriodTooltipData, ({int year, int month})>((ref, params) async {
  final allInvoices = await ref.watch(invoicesProvider.future);
  final inv = allInvoices.where((i) =>
    i.fecha.year == params.year && i.fecha.month == params.month &&
    i.status == InvoiceStatus.pagada
  ).toList();

  return PeriodTooltipData(
    label: _monthNames[params.month],
    totalCobrado: inv.fold(0.0, (s, i) => s + i.total),
    totalIva: inv.fold(0.0, (s, i) => s + i.ivaAmount),
    numFacturas: inv.length,
  );
});

final quarterTooltipProvider =
    FutureProvider.family<PeriodTooltipData, ({int year, int quarter})>((ref, params) async {
  final allInvoices = await ref.watch(invoicesProvider.future);
  final startM = (params.quarter - 1) * 3 + 1;
  final endM = params.quarter * 3;
  final inv = allInvoices.where((i) =>
    i.fecha.year == params.year &&
    i.fecha.month >= startM && i.fecha.month <= endM &&
    i.status == InvoiceStatus.pagada
  ).toList();

  return PeriodTooltipData(
    label: 'T${params.quarter}',
    totalCobrado: inv.fold(0.0, (s, i) => s + i.total),
    totalIva: inv.fold(0.0, (s, i) => s + i.ivaAmount),
    numFacturas: inv.length,
  );
});

// ==================== MONTHLY FINANCIAL DETAIL (bolos/IVA per month) ====================

class MonthlyFinancialDetail {
  final int month;
  final int year;
  final double iva;
  final int numBolos;
  final List<MonthlyGigDetail> gigs;

  MonthlyFinancialDetail({
    required this.month,
    required this.year,
    required this.iva,
    required this.numBolos,
    required this.gigs,
  });
}

class MonthlyGigDetail {
  final String gigId;
  final String clientName;
  final DateTime fecha;
  final double importe;
  final GigStatus status;

  MonthlyGigDetail({
    required this.gigId,
    required this.clientName,
    required this.fecha,
    required this.importe,
    required this.status,
  });
}

final monthlyFinancialDetailProvider =
    FutureProvider.family<MonthlyFinancialDetail, ({int year, int month})>((ref, params) async {
  final allInvoices = await ref.watch(invoicesProvider.future);
  final allGigs = await ref.watch(gigsProvider.future);

  final monthInvoices = allInvoices.where((i) =>
    i.fecha.year == params.year && i.fecha.month == params.month &&
    i.status == InvoiceStatus.pagada
  ).toList();

  final monthGigs = allGigs.where((g) =>
    g.fecha.year == params.year && g.fecha.month == params.month &&
    g.status != GigStatus.cancelado
  ).toList();

  final gigDetails = <MonthlyGigDetail>[];
  for (final gig in monthGigs) {
    final client = await ref.read(clientByIdProvider(gig.clientId).future);
    gigDetails.add(MonthlyGigDetail(
      gigId: gig.id,
      clientName: client?.nombre ?? 'Desconocido',
      fecha: gig.fecha,
      importe: gig.cachet ?? 0,
      status: gig.status,
    ));
  }

  return MonthlyFinancialDetail(
    month: params.month,
    year: params.year,
    iva: monthInvoices.fold(0.0, (s, i) => s + i.ivaAmount),
    numBolos: monthGigs.length,
    gigs: gigDetails,
  );
});

class ClientStats {
  final String clientId;
  final String clientName;
  final double totalOficial;
  final double totalEnB;
  final int totalBolos;

  ClientStats({
    required this.clientId,
    required this.clientName,
    this.totalOficial = 0,
    this.totalEnB = 0,
    this.totalBolos = 0,
  });
}

// ==================== ESTADÍSTICAS FINANCIERAS ====================

class FinancialStats {
  final int year;
  final double pendienteCobrar;     // Facturas enviadas no pagadas (histórico)
  final double cobrado;             // Facturas pagadas
  final double estimado;            // Cobrado + Pendiente + Bolos cerrados sin facturar
  final double cobradoEnB;          // Cobrado en B
  final List<MonthlyFinancialStats> porMes;

  FinancialStats({
    required this.year,
    this.pendienteCobrar = 0,
    this.cobrado = 0,
    this.estimado = 0,
    this.cobradoEnB = 0,
    this.porMes = const [],
  });
}

class MonthlyFinancialStats {
  final int month;
  final double pendienteCobrar;
  final double cobrado;
  final double estimado;
  final double cobradoEnB;

  MonthlyFinancialStats({
    required this.month,
    this.pendienteCobrar = 0,
    this.cobrado = 0,
    this.estimado = 0,
    this.cobradoEnB = 0,
  });

  double get total => cobrado + cobradoEnB;
}

final selectedYearProvider = StateProvider<int>((ref) => DateTime.now().year);

final financialStatsProvider = FutureProvider.family<FinancialStats, int>((ref, year) async {
  final allGigs = await ref.watch(gigsProvider.future);
  final allInvoices = await ref.watch(invoicesProvider.future);

  // Filtrar gigs del año (excepto cancelados)
  final gigsYear = allGigs.where((g) => 
    g.fecha.year == year && g.status != GigStatus.cancelado
  ).toList();

  // Facturas del año
  final invoicesYear = allInvoices.where((i) => i.fecha.year == year).toList();

  // === TOTALES ANUALES ===
  
  // Pendiente por cobrar: facturas enviadas pero no pagadas (todo el historial para el año)
  double pendienteCobrarTotal = 0;
  for (final inv in invoicesYear) {
    if (inv.status == InvoiceStatus.enviada) {
      pendienteCobrarTotal += inv.total;
    }
  }

  // Cobrado: facturas pagadas del año
  double cobradoTotal = 0;
  for (final inv in invoicesYear) {
    if (inv.status == InvoiceStatus.pagada) {
      cobradoTotal += inv.total;
    }
  }

  // Cobrado en B: gigs del año marcados como cobrado en B
  double cobradoEnBTotal = 0;
  for (final gig in gigsYear) {
    if (!gig.facturable && gig.status == GigStatus.cobradoEnB) {
      cobradoEnBTotal += gig.cachet ?? 0;
    }
  }

  // Estimado: cobrado + pendiente + bolos cerrados sin facturar del año
  // Bolos cerrados sin facturar = facturables con status pendiente/factura_generada
  double bolosSinFacturar = 0;
  for (final gig in gigsYear) {
    if (gig.facturable && 
        (gig.status == GigStatus.pendiente || gig.status == GigStatus.facturaGenerada)) {
      bolosSinFacturar += gig.cachet ?? 0;
    }
  }
  double estimadoTotal = cobradoTotal + pendienteCobrarTotal + bolosSinFacturar;

  // === POR MESES ===
  final porMes = <MonthlyFinancialStats>[];
  
  for (int m = 1; m <= 12; m++) {
    final gigsMonth = gigsYear.where((g) => g.fecha.month == m).toList();
    final invoicesMonth = invoicesYear.where((i) => i.fecha.month == m).toList();

    double pendienteMes = 0;
    for (final inv in invoicesMonth) {
      if (inv.status == InvoiceStatus.enviada) {
        pendienteMes += inv.total;
      }
    }

    double cobradoMes = 0;
    for (final inv in invoicesMonth) {
      if (inv.status == InvoiceStatus.pagada) {
        cobradoMes += inv.total;
      }
    }

    double cobradoEnBMes = 0;
    for (final gig in gigsMonth) {
      if (!gig.facturable && gig.status == GigStatus.cobradoEnB) {
        cobradoEnBMes += gig.cachet ?? 0;
      }
    }

    double sinFacturarMes = 0;
    for (final gig in gigsMonth) {
      if (gig.facturable && 
          (gig.status == GigStatus.pendiente || gig.status == GigStatus.facturaGenerada)) {
        sinFacturarMes += gig.cachet ?? 0;
      }
    }

    porMes.add(MonthlyFinancialStats(
      month: m,
      pendienteCobrar: pendienteMes,
      cobrado: cobradoMes,
      estimado: cobradoMes + pendienteMes + sinFacturarMes,
      cobradoEnB: cobradoEnBMes,
    ));
  }

  return FinancialStats(
    year: year,
    pendienteCobrar: pendienteCobrarTotal,
    cobrado: cobradoTotal,
    estimado: estimadoTotal,
    cobradoEnB: cobradoEnBTotal,
    porMes: porMes,
  );
});

// ==================== IVA TRIMESTRAL ====================

class QuarterlyVat {
  final int quarter;           // 1-4
  final int year;
  final double ivaAcumulado;
  final DateTime declarationDate;
  final int daysRemaining;
  final String quarterLabel;   // "T2 · abril — junio 2026"

  QuarterlyVat({
    required this.quarter,
    required this.year,
    required this.ivaAcumulado,
    required this.declarationDate,
    required this.daysRemaining,
    required this.quarterLabel,
  });
}

const _monthNames = [
  '', 'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

final quarterlyVatProvider = FutureProvider<QuarterlyVat>((ref) async {
  final now = DateTime.now();
  final quarter = ((now.month - 1) ~/ 3) + 1;
  final startMonth = (quarter - 1) * 3 + 1;
  final endMonth = quarter * 3;

  final allInvoices = await ref.watch(invoicesProvider.future);

  double ivaAcum = 0;
  for (final inv in allInvoices) {
    if (inv.fecha.year == now.year &&
        inv.fecha.month >= startMonth &&
        inv.fecha.month <= endMonth &&
        inv.status == InvoiceStatus.pagada) {
      ivaAcum += inv.ivaAmount;
    }
  }

  // Fecha declaración: T1→20 abr, T2→20 jul, T3→20 oct, T4→30 ene año siguiente
  late DateTime declDate;
  switch (quarter) {
    case 1: declDate = DateTime(now.year, 4, 20); break;
    case 2: declDate = DateTime(now.year, 7, 20); break;
    case 3: declDate = DateTime(now.year, 10, 20); break;
    case 4: declDate = DateTime(now.year + 1, 1, 30); break;
  }

  final daysLeft = declDate.difference(DateTime(now.year, now.month, now.day)).inDays;

  final label = 'T$quarter · ${_monthNames[startMonth]} — ${_monthNames[endMonth]} ${now.year}';

  return QuarterlyVat(
    quarter: quarter,
    year: now.year,
    ivaAcumulado: ivaAcum,
    declarationDate: declDate,
    daysRemaining: daysLeft,
    quarterLabel: label,
  );
});

// ==================== FACTURAS PENDIENTES VENCIDAS ====================

class OverdueInvoice {
  final Invoice invoice;
  final String clientName;
  final int daysSinceSent;

  OverdueInvoice({
    required this.invoice,
    required this.clientName,
    required this.daysSinceSent,
  });
}

class OverdueAlert {
  final List<OverdueInvoice> invoices;
  final bool hasOver30Days;

  OverdueAlert({required this.invoices})
      : hasOver30Days = invoices.any((i) => i.daysSinceSent > 30);
}

final overdueInvoicesProvider = FutureProvider<OverdueAlert>((ref) async {
  final allInvoices = await ref.watch(invoicesProvider.future);
  final now = DateTime.now();

  final enviadas = allInvoices.where((i) => i.status == InvoiceStatus.enviada).toList();
  final overdue = <OverdueInvoice>[];

  for (final inv in enviadas) {
    final days = now.difference(inv.fecha).inDays;
    if (days > 7) {
      final client = await ref.read(clientByIdProvider(inv.clientId).future);
      overdue.add(OverdueInvoice(
        invoice: inv,
        clientName: client?.nombre ?? 'Cliente desconocido',
        daysSinceSent: days,
      ));
    }
  }

  overdue.sort((a, b) => b.daysSinceSent.compareTo(a.daysSinceSent));
  return OverdueAlert(invoices: overdue);
});

// ==================== RACHA / ACTIVIDAD ====================

class ActivityStreak {
  final int daysSinceLastGig;
  
  ActivityStreak({required this.daysSinceLastGig});
}

final activityStreakProvider = FutureProvider<ActivityStreak>((ref) async {
  final allGigs = await ref.watch(gigsProvider.future);
  if (allGigs.isEmpty) return ActivityStreak(daysSinceLastGig: -1);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  
  // Último bolo registrado (más reciente por fecha de creación)
  final sorted = [...allGigs]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final lastGig = sorted.first;
  final lastDate = DateTime(lastGig.createdAt.year, lastGig.createdAt.month, lastGig.createdAt.day);
  
  return ActivityStreak(daysSinceLastGig: today.difference(lastDate).inDays);
});

// ==================== FINANCIAL SUMMARY PERIOD ====================

final financialPeriodProvider = StateProvider<DashboardPeriod>((ref) {
  final now = DateTime.now();
  return DashboardPeriod(
    mode: DashboardPeriodMode.anio,
    year: now.year,
    month: now.month,
    quarter: ((now.month - 1) ~/ 3) + 1,
  );
});

/// Detailed financial summary for any period, used by the financial summary screen.
class FinancialPeriodSummary {
  final DashboardPeriod period;
  final double cobradoOficial;
  final double pendienteCobrar;
  final double cobradoEnB;
  final double pendienteEnB;
  final double estimado;
  final double ivaTotal;
  final int numBolos;
  final int numFacturasPagadas;
  final int numFacturasEnviadas;
  // Sub-period breakdown
  final List<SubPeriodStats> subPeriods;
  // IVA breakdown per quarter (for trimestre/anio modes)
  final List<QuarterVatDetail> ivaQuarters;
  // Comparison with previous period
  final double? prevCobradoTotal;
  final String? prevLabel;

  FinancialPeriodSummary({
    required this.period,
    this.cobradoOficial = 0,
    this.pendienteCobrar = 0,
    this.cobradoEnB = 0,
    this.pendienteEnB = 0,
    this.estimado = 0,
    this.ivaTotal = 0,
    this.numBolos = 0,
    this.numFacturasPagadas = 0,
    this.numFacturasEnviadas = 0,
    this.subPeriods = const [],
    this.ivaQuarters = const [],
    this.prevCobradoTotal,
    this.prevLabel,
  });

  double get totalCobrado => cobradoOficial + cobradoEnB;
}

class SubPeriodStats {
  final String label;     // "Ene", "T1", etc.
  final int index;        // month 1-12 or quarter 1-4
  final double cobrado;
  final double pendiente;
  final double cobradoEnB;
  final double estimado;
  final int numBolos;
  final List<MonthlyGigDetail> gigs;

  SubPeriodStats({
    required this.label,
    required this.index,
    this.cobrado = 0,
    this.pendiente = 0,
    this.cobradoEnB = 0,
    this.estimado = 0,
    this.numBolos = 0,
    this.gigs = const [],
  });

  double get total => cobrado + cobradoEnB;
  bool get hasData => cobrado > 0 || pendiente > 0 || cobradoEnB > 0 || estimado > 0;
}

const _shortMonths = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

final financialPeriodSummaryProvider =
    FutureProvider.family<FinancialPeriodSummary, DashboardPeriod>((ref, period) async {
  final allGigs = await ref.watch(gigsProvider.future);
  final allInvoices = await ref.watch(invoicesProvider.future);

  final stats = _calcPeriodStats(period, allGigs, allInvoices);

  // Count invoices
  final (start, end) = _periodRange(period);
  final invoicesInPeriod = allInvoices.where((i) =>
    !i.fecha.isBefore(start) && !i.fecha.isAfter(end)
  ).toList();
  int numPagadas = invoicesInPeriod.where((i) => i.status == InvoiceStatus.pagada).length;
  int numEnviadas = invoicesInPeriod.where((i) => i.status == InvoiceStatus.enviada).length;

  // IVA quarters (only for trimestre and anio modes)
  List<QuarterVatDetail> ivaQuarters = [];
  if (period.mode == DashboardPeriodMode.trimestre || period.mode == DashboardPeriodMode.anio) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentQuarter = ((now.month - 1) ~/ 3) + 1;

    int qStart, qEnd;
    if (period.mode == DashboardPeriodMode.trimestre) {
      qStart = period.quarter;
      qEnd = period.quarter;
    } else {
      qStart = 1;
      qEnd = 4;
    }

    for (int q = qStart; q <= qEnd; q++) {
      final sM = (q - 1) * 3 + 1;
      final eM = q * 3;

      final qInvoices = allInvoices.where((inv) =>
        inv.fecha.year == period.year &&
        inv.fecha.month >= sM && inv.fecha.month <= eM &&
        inv.status == InvoiceStatus.pagada
      ).toList();

      double ivaTotal = 0;
      final invoiceDetails = <QuarterVatInvoice>[];
      for (final inv in qInvoices) {
        ivaTotal += inv.ivaAmount;
        final client = await ref.read(clientByIdProvider(inv.clientId).future);
        invoiceDetails.add(QuarterVatInvoice(
          invoiceId: inv.id,
          numero: inv.numero,
          clientName: client?.nombre ?? 'Cliente desconocido',
          fecha: inv.fecha,
          base: inv.subtotal,
          iva: inv.ivaAmount,
        ));
      }

      final declDate = _declarationDate(q, period.year);
      final daysLeft = declDate.difference(today).inDays;

      String status;
      if (period.year < now.year || (period.year == now.year && q < currentQuarter)) {
        status = daysLeft < 0 && ivaTotal > 0 ? 'pendiente_declarar' : 'pasado';
      } else if (period.year == now.year && q == currentQuarter) {
        status = 'en_curso';
      } else {
        status = 'proximo';
      }

      ivaQuarters.add(QuarterVatDetail(
        quarter: q,
        year: period.year,
        ivaTotal: ivaTotal,
        declarationDate: declDate,
        daysRemaining: daysLeft,
        status: status,
        invoices: invoiceDetails,
      ));
    }
  }

  // Sub-periods
  List<SubPeriodStats> subPeriods = [];
  if (period.mode == DashboardPeriodMode.anio) {
    // Monthly breakdown
    for (int m = 1; m <= 12; m++) {
      final mGigs = allGigs.where((g) =>
        g.fecha.year == period.year && g.fecha.month == m &&
        g.status != GigStatus.cancelado
      ).toList();
      final mInvoices = allInvoices.where((i) =>
        i.fecha.year == period.year && i.fecha.month == m
      ).toList();

      double cobrado = 0, pendiente = 0, enB = 0;
      for (final inv in mInvoices) {
        if (inv.status == InvoiceStatus.pagada) {
          cobrado += inv.total;
        } else if (inv.status == InvoiceStatus.enviada) {
          pendiente += inv.total;
        }
      }
      for (final gig in mGigs) {
        final cachet = gig.cachet ?? 0;
        if (gig.facturable && (gig.status == GigStatus.pendiente || gig.status == GigStatus.facturaGenerada)) {
          pendiente += cachet;
        }
        if (!gig.facturable && gig.status == GigStatus.cobradoEnB) {
          enB += cachet;
        }
        if (!gig.facturable && gig.status == GigStatus.pendiente) {
          pendiente += cachet;
        }
      }

      final gigDetails = <MonthlyGigDetail>[];
      for (final gig in mGigs) {
        final client = await ref.read(clientByIdProvider(gig.clientId).future);
        gigDetails.add(MonthlyGigDetail(
          gigId: gig.id,
          clientName: client?.nombre ?? 'Desconocido',
          fecha: gig.fecha,
          importe: gig.cachet ?? 0,
          status: gig.status,
        ));
      }

      subPeriods.add(SubPeriodStats(
        label: _shortMonths[m - 1],
        index: m,
        cobrado: cobrado,
        pendiente: pendiente,
        cobradoEnB: enB,
        estimado: cobrado + pendiente + enB,
        numBolos: mGigs.length,
        gigs: gigDetails,
      ));
    }
  } else if (period.mode == DashboardPeriodMode.trimestre) {
    // Monthly breakdown for the quarter
    final startM = (period.quarter - 1) * 3 + 1;
    for (int m = startM; m < startM + 3; m++) {
      final mGigs = allGigs.where((g) =>
        g.fecha.year == period.year && g.fecha.month == m &&
        g.status != GigStatus.cancelado
      ).toList();
      final mInvoices = allInvoices.where((i) =>
        i.fecha.year == period.year && i.fecha.month == m
      ).toList();

      double cobrado = 0, pendiente = 0, enB = 0;
      for (final inv in mInvoices) {
        if (inv.status == InvoiceStatus.pagada) {
          cobrado += inv.total;
        } else if (inv.status == InvoiceStatus.enviada) {
          pendiente += inv.total;
        }
      }
      for (final gig in mGigs) {
        final cachet = gig.cachet ?? 0;
        if (gig.facturable && (gig.status == GigStatus.pendiente || gig.status == GigStatus.facturaGenerada)) {
          pendiente += cachet;
        }
        if (!gig.facturable && gig.status == GigStatus.cobradoEnB) {
          enB += cachet;
        }
        if (!gig.facturable && gig.status == GigStatus.pendiente) {
          pendiente += cachet;
        }
      }

      final gigDetails = <MonthlyGigDetail>[];
      for (final gig in mGigs) {
        final client = await ref.read(clientByIdProvider(gig.clientId).future);
        gigDetails.add(MonthlyGigDetail(
          gigId: gig.id,
          clientName: client?.nombre ?? 'Desconocido',
          fecha: gig.fecha,
          importe: gig.cachet ?? 0,
          status: gig.status,
        ));
      }

      subPeriods.add(SubPeriodStats(
        label: _shortMonths[m - 1],
        index: m,
        cobrado: cobrado,
        pendiente: pendiente,
        cobradoEnB: enB,
        estimado: cobrado + pendiente + enB,
        numBolos: mGigs.length,
        gigs: gigDetails,
      ));
    }
  }
  // Month mode: no sub-periods, but include gigs
  if (period.mode == DashboardPeriodMode.mes) {
    final mGigs = allGigs.where((g) =>
      g.fecha.year == period.year && g.fecha.month == period.month &&
      g.status != GigStatus.cancelado
    ).toList();

    final gigDetails = <MonthlyGigDetail>[];
    for (final gig in mGigs) {
      final client = await ref.read(clientByIdProvider(gig.clientId).future);
      gigDetails.add(MonthlyGigDetail(
        gigId: gig.id,
        clientName: client?.nombre ?? 'Desconocido',
        fecha: gig.fecha,
        importe: gig.cachet ?? 0,
        status: gig.status,
      ));
    }

    subPeriods.add(SubPeriodStats(
      label: _shortMonths[period.month - 1],
      index: period.month,
      cobrado: stats.cobradoOficial,
      pendiente: stats.pendienteOficial,
      cobradoEnB: stats.cobradoEnB,
      estimado: stats.estimado,
      numBolos: stats.totalBolos,
      gigs: gigDetails,
    ));
  }

  // Previous period comparison
  final prev = period.previous;
  final prevStats = _calcPeriodStats(prev, allGigs, allInvoices);
  final hasPrev = prevStats.totalCobrado > 0;

  return FinancialPeriodSummary(
    period: period,
    cobradoOficial: stats.cobradoOficial,
    pendienteCobrar: stats.pendienteOficial,
    cobradoEnB: stats.cobradoEnB,
    pendienteEnB: stats.pendienteEnB,
    estimado: stats.estimado,
    ivaTotal: stats.ivaAcumulado,
    numBolos: stats.totalBolos,
    numFacturasPagadas: numPagadas,
    numFacturasEnviadas: numEnviadas,
    subPeriods: subPeriods,
    ivaQuarters: ivaQuarters,
    prevCobradoTotal: hasPrev ? prevStats.totalCobrado : null,
    prevLabel: hasPrev ? prev.label : null,
  );
});
