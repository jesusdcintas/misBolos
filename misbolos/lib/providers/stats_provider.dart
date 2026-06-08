import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/period_utils.dart';
import '../database/database_helper.dart';
import '../models/client.dart';
import '../models/gig.dart';
import '../models/invoice.dart';
import 'client_provider.dart';
import 'gig_provider.dart';
import 'invoice_provider.dart';

// ==================== DECLARED QUARTERS ====================

/// Returns a Set of "year-quarter" strings for quarters marked as declared.
final declaredQuartersProvider =
    AsyncNotifierProvider<DeclaredQuartersNotifier, Set<String>>(
      DeclaredQuartersNotifier.new,
    );

class DeclaredQuartersNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('declared_quarters');
    return rows.map((r) => '${r['year']}-${r['quarter']}').toSet();
  }

  Future<void> toggle(int year, int quarter, {double? ivaAmount}) async {
    final db = await DatabaseHelper.instance.database;
    final key = '$year-$quarter';
    final current = state.valueOrNull ?? {};

    if (current.contains(key)) {
      await db.delete(
        'declared_quarters',
        where: 'year = ? AND quarter = ?',
        whereArgs: [year, quarter],
      );
    } else {
      await db.insert('declared_quarters', {
        'id': key,
        'year': year,
        'quarter': quarter,
        'declared_at': DateTime.now().toIso8601String(),
        'iva_amount': ivaAmount,
      });
    }
    ref.invalidateSelf();
  }
}

// ==================== DASHBOARD PERIOD ====================

enum DashboardPeriodMode { mes, trimestre, anio }

const _periodMonthNames = [
  '',
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

@immutable
class DashboardPeriod {
  final DashboardPeriodMode mode;
  final int year;
  final int month; // 1-12
  final int quarter; // 1-4

  const DashboardPeriod({
    required this.mode,
    required this.year,
    required this.month,
    required this.quarter,
  });

  DashboardPeriod copyWith({
    DashboardPeriodMode? mode,
    int? year,
    int? month,
    int? quarter,
  }) {
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
        final currentQ = PeriodUtils.currentQuarter(now);
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
    quarter: PeriodUtils.currentQuarter(now),
  );
});

// ==================== PERIOD-BASED DASHBOARD STATS ====================

class PeriodDashboardStats {
  // COBRADO = facturas pagadas + histórico sin factura + cobrado privado
  final double cobradoFacturas; // facturas pagadas (subtotal)
  final double
  cobradoHistorico; // gigs facturables cobrados sin factura (import Excel)
  final int cobradoHistoricoCount; // nº bolos históricos
  final double cobradoEnB; // gigs !facturable + cobradoEnB
  // PENDIENTE = solo facturas enviadas
  final double pendiente; // facturas status=enviada (total)
  final int pendienteCount; // nº facturas enviadas
  // PREVISTO = bolos futuros facturables sin factura emitida
  final double previsto; // cachet de gigs futuros
  final int previstoCount; // nº bolos futuros
  final double previstoConfirmado;
  final int previstoConfirmadoCount;
  final double previstoBorrador;
  final int previstoBorradorCount;
  // Privado
  final double pendienteEnB;
  final int pendienteEnBCount;
  final double previstoEnB;
  final int previstoEnBCount;
  final int totalBolos;
  final int numBolosB;
  final double ivaAcumulado;
  final double ivaHistoricoEstimado; // IVA estimado de bolos históricos
  // Previous period (for comparison)
  final double? prevCobrado;
  final String? prevLabel;

  PeriodDashboardStats({
    this.cobradoFacturas = 0,
    this.cobradoHistorico = 0,
    this.cobradoHistoricoCount = 0,
    this.cobradoEnB = 0,
    this.pendiente = 0,
    this.pendienteCount = 0,
    this.previsto = 0,
    this.previstoCount = 0,
    this.previstoConfirmado = 0,
    this.previstoConfirmadoCount = 0,
    this.previstoBorrador = 0,
    this.previstoBorradorCount = 0,
    this.pendienteEnB = 0,
    this.pendienteEnBCount = 0,
    this.previstoEnB = 0,
    this.previstoEnBCount = 0,
    this.totalBolos = 0,
    this.numBolosB = 0,
    this.ivaAcumulado = 0,
    this.ivaHistoricoEstimado = 0,
    this.prevCobrado,
    this.prevLabel,
  });

  double get cobradoOficial => cobradoFacturas + cobradoHistorico;
  double get cobrado => cobradoOficial + cobradoEnB;
  double get acumulado => cobradoOficial + pendiente;
  double get totalPrevisto => acumulado + previsto;
  double get acumuladoEnB => cobradoEnB + pendienteEnB;
  double get totalPrevistoEnB => acumuladoEnB + previstoEnB;
  double get pendienteTotal => pendiente + pendienteEnB;
  double get previstoTotal => previsto + previstoEnB;
  double get acumuladoTotal => cobrado + pendienteTotal;
  double get totalPrevistoGlobal => acumuladoTotal + previstoTotal;
  double get ivaTotalEstimado => ivaAcumulado + ivaHistoricoEstimado;
}

/// Returns (startDate, endDate) for the given period
(DateTime, DateTime) _periodRange(DashboardPeriod period) {
  switch (period.mode) {
    case DashboardPeriodMode.mes:
      return PeriodUtils.monthRange(period.year, period.month);
    case DashboardPeriodMode.trimestre:
      return PeriodUtils.quarterRange(period.year, period.quarter);
    case DashboardPeriodMode.anio:
      return PeriodUtils.yearRange(period.year);
  }
}

PeriodDashboardStats _calcPeriodStats(
  DashboardPeriod period,
  List<Gig> allGigs,
  List<Invoice> allInvoices,
) {
  final (start, end) = _periodRange(period);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final gigsInPeriod = allGigs
      .where(
        (g) =>
            !g.fecha.isBefore(start) &&
            !g.fecha.isAfter(end) &&
            g.status != GigStatus.cancelado,
      )
      .toList();

  final invoicesInPeriod = allInvoices
      .where((i) => !i.fecha.isBefore(start) && !i.fecha.isAfter(end))
      .toList();
  final invoiceByGigId = {for (final inv in invoicesInPeriod) inv.gigId: inv};

  // COBRADO (facturas pagadas)
  double cobradoFacturas = 0;
  // PENDIENTE (solo facturas enviadas)
  double pendiente = 0;
  int pendienteCount = 0;

  for (final inv in invoicesInPeriod) {
    if (inv.status == InvoiceStatus.pagada) {
      cobradoFacturas += inv.total;
    } else if (inv.status == InvoiceStatus.enviada) {
      pendiente += inv.total;
      pendienteCount++;
    }
  }

  // COBRADO HISTÓRICO: bolos facturables cobrados SIN factura (importados Excel)
  double cobradoHistorico = 0;
  int cobradoHistoricoCount = 0;
  for (final gig in gigsInPeriod) {
    if (gig.facturable &&
        gig.status == GigStatus.cobrado &&
        (gig.invoiceId == null || gig.invoiceId!.isEmpty)) {
      cobradoHistorico += gig.cachet ?? 0;
      cobradoHistoricoCount++;
    }
  }

  // PREVISTO = bolos facturables futuros sin factura emitida
  double previsto = 0;
  int previstoCount = 0;
  double previstoConfirmado = 0;
  int previstoConfirmadoCount = 0;
  double previstoBorrador = 0;
  int previstoBorradorCount = 0;
  for (final gig in gigsInPeriod) {
    final cachet = gig.cachet ?? 0;
    final gigDate = DateTime(gig.fecha.year, gig.fecha.month, gig.fecha.day);
    final linkedInvoice = invoiceByGigId[gig.id];
    final hasDraftInvoice = linkedInvoice?.status == InvoiceStatus.borrador;
    if (!gig.facturable || gigDate.isBefore(today)) continue;
    if (gig.status == GigStatus.confirmado) {
      previsto += cachet;
      previstoCount++;
      previstoConfirmado += cachet;
      previstoConfirmadoCount++;
    } else if (gig.status == GigStatus.facturado && hasDraftInvoice) {
      previsto += cachet;
      previstoCount++;
      previstoBorrador += cachet;
      previstoBorradorCount++;
    }
  }

  // Cobrado privado + pendiente privado + previsto privado
  double cobradoEnB = 0;
  double pendienteEnB = 0;
  int pendienteEnBCount = 0;
  double previstoEnB = 0;
  int previstoEnBCount = 0;
  int numBolosB = 0;
  for (final gig in gigsInPeriod) {
    final cachet = gig.cachet ?? 0;
    if (!gig.facturable) {
      if (gig.status == GigStatus.cobradoB) {
        cobradoEnB += cachet;
        numBolosB++;
      } else if (gig.status == GigStatus.realizadoB) {
        pendienteEnB += cachet;
        pendienteEnBCount++;
        numBolosB++;
      } else if (gig.status == GigStatus.confirmadoB) {
        previstoEnB += cachet;
        previstoEnBCount++;
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

  // IVA estimado de bolos históricos (cachet ÷ 1.21 × 0.21)
  double ivaHistorico = cobradoHistorico > 0
      ? cobradoHistorico / 1.21 * 0.21
      : 0;

  return PeriodDashboardStats(
    cobradoFacturas: cobradoFacturas,
    cobradoHistorico: cobradoHistorico,
    cobradoHistoricoCount: cobradoHistoricoCount,
    cobradoEnB: cobradoEnB,
    pendiente: pendiente,
    pendienteCount: pendienteCount,
    previsto: previsto,
    previstoCount: previstoCount,
    previstoConfirmado: previstoConfirmado,
    previstoConfirmadoCount: previstoConfirmadoCount,
    previstoBorrador: previstoBorrador,
    previstoBorradorCount: previstoBorradorCount,
    pendienteEnB: pendienteEnB,
    pendienteEnBCount: pendienteEnBCount,
    previstoEnB: previstoEnB,
    previstoEnBCount: previstoEnBCount,
    totalBolos: gigsInPeriod.length,
    numBolosB: numBolosB,
    ivaAcumulado: iva,
    ivaHistoricoEstimado: ivaHistorico,
  );
}

final periodDashboardStatsProvider =
    FutureProvider.family<PeriodDashboardStats, DashboardPeriod>((
      ref,
      period,
    ) async {
      final allGigs = await ref.watch(gigsProvider.future);
      final allInvoices = await ref.watch(invoicesProvider.future);

      final stats = _calcPeriodStats(period, allGigs, allInvoices);

      // Previous period comparison
      final prev = period.previous;
      final prevStats = _calcPeriodStats(prev, allGigs, allInvoices);
      final hasPrev = prevStats.cobrado > 0 || prevStats.cobradoFacturas > 0;

      return PeriodDashboardStats(
        cobradoFacturas: stats.cobradoFacturas,
        cobradoHistorico: stats.cobradoHistorico,
        cobradoHistoricoCount: stats.cobradoHistoricoCount,
        cobradoEnB: stats.cobradoEnB,
        pendiente: stats.pendiente,
        pendienteCount: stats.pendienteCount,
        previsto: stats.previsto,
        previstoCount: stats.previstoCount,
        previstoConfirmado: stats.previstoConfirmado,
        previstoConfirmadoCount: stats.previstoConfirmadoCount,
        previstoBorrador: stats.previstoBorrador,
        previstoBorradorCount: stats.previstoBorradorCount,
        pendienteEnB: stats.pendienteEnB,
        pendienteEnBCount: stats.pendienteEnBCount,
        previstoEnB: stats.previstoEnB,
        previstoEnBCount: stats.previstoEnBCount,
        totalBolos: stats.totalBolos,
        numBolosB: stats.numBolosB,
        ivaAcumulado: stats.ivaAcumulado,
        ivaHistoricoEstimado: stats.ivaHistoricoEstimado,
        prevCobrado: hasPrev ? prevStats.cobrado : null,
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
  final invoicesMonth = allInvoices
      .where((i) => i.fecha.year == now.year && i.fecha.month == now.month)
      .toList();

  // Mes anterior
  final prevMonth = now.month == 1 ? 12 : now.month - 1;
  final prevYear = now.month == 1 ? now.year - 1 : now.year;
  final invoicesPrev = allInvoices
      .where((i) => i.fecha.year == prevYear && i.fecha.month == prevMonth)
      .toList();
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

  // En oficial pendiente solo cuentan facturas emitidas y no cobradas.
  for (final gig in gigs) {
    final cachet = gig.cachet ?? 0;
    if (!gig.facturable) {
      // Ingresos privados - siguen basándose en el gig
      if (gig.status == GigStatus.cobradoB) {
        cobradoEnB += cachet;
      } else if (gig.status == GigStatus.realizadoB) {
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
  // Mantenemos la misma regla en mes anterior: pendiente oficial = facturas enviadas.

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

final yearlyStatsProvider = FutureProvider.family<List<MonthlyIncome>, int>((
  ref,
  year,
) async {
  final allGigs = await ref.watch(gigsProvider.future);
  final months = <MonthlyIncome>[];

  for (int m = 1; m <= 12; m++) {
    double oficial = 0;
    double enB = 0;

    for (final gig in allGigs) {
      if (gig.fecha.year == year && gig.fecha.month == m) {
        final cachet = gig.cachet ?? 0;
        if (gig.facturable && gig.status == GigStatus.cobrado) {
          oficial += cachet;
        } else if (!gig.facturable && gig.status == GigStatus.cobradoB) {
          enB += cachet;
        }
      }
    }

    months.add(MonthlyIncome(year: year, month: m, oficial: oficial, enB: enB));
  }

  return months;
});

final ivaAcumuladoProvider = FutureProvider.family<double, int>((
  ref,
  year,
) async {
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
        quarters.add(
          QuarterlyIncome(quarter: q, year: year, oficial: oficial, enB: enB),
        );
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
  final double ivaFacturas; // IVA real de facturas
  final double ivaHistoricoEstimado; // IVA estimado de bolos históricos
  final bool isEstimated; // true si incluye IVA estimado
  final bool isDeclared; // marcado manualmente como declarado
  final DateTime declarationDate;
  final int daysRemaining;
  final String
  status; // 'pendiente_declarar', 'en_curso', 'proximo', 'pasado', 'declarado'
  final List<QuarterVatInvoice> invoices;

  QuarterVatDetail({
    required this.quarter,
    required this.year,
    required this.ivaTotal,
    this.ivaFacturas = 0,
    this.ivaHistoricoEstimado = 0,
    this.isEstimated = false,
    this.isDeclared = false,
    required this.declarationDate,
    required this.daysRemaining,
    required this.status,
    required this.invoices,
  });
}

DateTime _declarationDate(int quarter, int year) {
  switch (quarter) {
    case 1:
      return DateTime(year, 4, 20);
    case 2:
      return DateTime(year, 7, 20);
    case 3:
      return DateTime(year, 10, 20);
    case 4:
      return DateTime(year + 1, 1, 30);
    default:
      return DateTime(year, 4, 20);
  }
}

final yearlyVatDetailProvider =
    FutureProvider.family<List<QuarterVatDetail>, int>((ref, year) async {
      final allInvoices = await ref.watch(invoicesProvider.future);
      final allGigs = await ref.watch(gigsProvider.future);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final currentQuarter = PeriodUtils.currentQuarter(now);
      final declaredSet = await ref.watch(declaredQuartersProvider.future);

      final result = <QuarterVatDetail>[];

      for (int q = 1; q <= 4; q++) {
        final startM = (q - 1) * 3 + 1;
        final endM = q * 3;

        final qInvoices = allInvoices
            .where(
              (inv) =>
                  inv.fecha.year == year &&
                  inv.fecha.month >= startM &&
                  inv.fecha.month <= endM &&
                  inv.status == InvoiceStatus.pagada,
            )
            .toList();

        double ivaFacturas = 0;
        final invoiceDetails = <QuarterVatInvoice>[];
        for (final inv in qInvoices) {
          ivaFacturas += inv.ivaAmount;
          final client = await ref.read(
            clientByIdProvider(inv.clientId).future,
          );
          invoiceDetails.add(
            QuarterVatInvoice(
              invoiceId: inv.id,
              numero: inv.numero,
              clientName: client?.displayName ?? 'Cliente desconocido',
              fecha: inv.fecha,
              base: inv.subtotal,
              iva: inv.ivaAmount,
            ),
          );
        }

        // Historical gigs
        final qHistoricGigs = allGigs
            .where(
              (g) =>
                  g.fecha.year == year &&
                  g.fecha.month >= startM &&
                  g.fecha.month <= endM &&
                  g.facturable &&
                  g.status == GigStatus.cobrado &&
                  (g.invoiceId == null || g.invoiceId!.isEmpty),
            )
            .toList();
        double baseHistorico = 0;
        for (final gig in qHistoricGigs) {
          baseHistorico += (gig.cachet ?? 0);
        }
        final ivaHistorico = baseHistorico > 0
            ? baseHistorico / 1.21 * 0.21
            : 0.0;
        final isEstimated = ivaHistorico > 0;
        final ivaTotal = ivaFacturas + ivaHistorico;

        final declDate = _declarationDate(q, year);
        final daysLeft = declDate.difference(today).inDays;

        final isDeclared = declaredSet.contains('$year-$q');

        String status;
        if (isDeclared) {
          status = 'declarado';
        } else if (year < now.year ||
            (year == now.year && q < currentQuarter)) {
          status = daysLeft < 0 && ivaTotal > 0
              ? 'pendiente_declarar'
              : 'pasado';
        } else if (year == now.year && q == currentQuarter) {
          status = 'en_curso';
        } else {
          status = 'proximo';
        }

        result.add(
          QuarterVatDetail(
            quarter: q,
            year: year,
            ivaTotal: ivaTotal,
            ivaFacturas: ivaFacturas,
            ivaHistoricoEstimado: ivaHistorico,
            isEstimated: isEstimated,
            isDeclared: isDeclared,
            declarationDate: declDate,
            daysRemaining: daysLeft,
            status: status,
            invoices: invoiceDetails,
          ),
        );
      }

      return result;
    });

// ==================== TOOLTIP DATA (mes o trimestre pulsado) ====================

class PeriodTooltipData {
  final String label;
  final double totalCobrado;
  final double totalIva;
  final int numFacturas;
  final double? totalOficial;
  final double? totalPrivado;

  PeriodTooltipData({
    required this.label,
    required this.totalCobrado,
    required this.totalIva,
    required this.numFacturas,
    this.totalOficial,
    this.totalPrivado,
  });

  bool get hasGlobalBreakdown => totalOficial != null || totalPrivado != null;
}

final monthTooltipProvider =
    FutureProvider.family<PeriodTooltipData, ({int year, int month})>((
      ref,
      params,
    ) async {
      final allInvoices = await ref.watch(invoicesProvider.future);
      final inv = allInvoices
          .where(
            (i) =>
                i.fecha.year == params.year &&
                i.fecha.month == params.month &&
                i.status == InvoiceStatus.pagada,
          )
          .toList();

      return PeriodTooltipData(
        label: _monthNames[params.month],
        totalCobrado: inv.fold(0.0, (s, i) => s + i.total),
        totalIva: inv.fold(0.0, (s, i) => s + i.ivaAmount),
        numFacturas: inv.length,
      );
    });

final quarterTooltipProvider =
    FutureProvider.family<PeriodTooltipData, ({int year, int quarter})>((
      ref,
      params,
    ) async {
      final allInvoices = await ref.watch(invoicesProvider.future);
      final startM = (params.quarter - 1) * 3 + 1;
      final endM = params.quarter * 3;
      final inv = allInvoices
          .where(
            (i) =>
                i.fecha.year == params.year &&
                i.fecha.month >= startM &&
                i.fecha.month <= endM &&
                i.status == InvoiceStatus.pagada,
          )
          .toList();

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
    FutureProvider.family<MonthlyFinancialDetail, ({int year, int month})>((
      ref,
      params,
    ) async {
      final allInvoices = await ref.watch(invoicesProvider.future);
      final allGigs = await ref.watch(gigsProvider.future);

      final monthInvoices = allInvoices
          .where(
            (i) =>
                i.fecha.year == params.year &&
                i.fecha.month == params.month &&
                i.status == InvoiceStatus.pagada,
          )
          .toList();

      final monthGigs = allGigs
          .where(
            (g) =>
                g.fecha.year == params.year &&
                g.fecha.month == params.month &&
                g.status != GigStatus.cancelado,
          )
          .toList();

      final gigDetails = <MonthlyGigDetail>[];
      for (final gig in monthGigs) {
        final client = await ref.read(clientByIdProvider(gig.clientId).future);
        gigDetails.add(
          MonthlyGigDetail(
            gigId: gig.id,
            clientName: client?.displayName ?? 'Desconocido',
            fecha: gig.fecha,
            importe: gig.cachet ?? 0,
            status: gig.status,
          ),
        );
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
  final double pendienteCobrar; // Facturas enviadas no pagadas (histórico)
  final double cobrado; // Facturas pagadas
  final double estimado; // Cobrado + Pendiente + Bolos cerrados sin facturar
  final double cobradoEnB; // Cobrado privado
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

final financialStatsProvider = FutureProvider.family<FinancialStats, int>((
  ref,
  year,
) async {
  final allGigs = await ref.watch(gigsProvider.future);
  final allInvoices = await ref.watch(invoicesProvider.future);

  // Filtrar gigs del año (excepto cancelados)
  final gigsYear = allGigs
      .where((g) => g.fecha.year == year && g.status != GigStatus.cancelado)
      .toList();

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

  // Cobrado privado: gigs del año marcados como cobrado privado
  double cobradoEnBTotal = 0;
  for (final gig in gigsYear) {
    if (!gig.facturable && gig.status == GigStatus.cobradoB) {
      cobradoEnBTotal += gig.cachet ?? 0;
    }
  }

  // Estimado: cobrado + pendiente + bolos cerrados sin facturar del año
  // Bolos cerrados sin facturar = facturables con status confirmado
  double bolosSinFacturar = 0;
  for (final gig in gigsYear) {
    if (gig.facturable &&
        gig.status == GigStatus.confirmado) {
      bolosSinFacturar += gig.cachet ?? 0;
    }
  }
  double estimadoTotal = cobradoTotal + pendienteCobrarTotal + bolosSinFacturar;

  // === POR MESES ===
  final porMes = <MonthlyFinancialStats>[];

  for (int m = 1; m <= 12; m++) {
    final gigsMonth = gigsYear.where((g) => g.fecha.month == m).toList();
    final invoicesMonth = invoicesYear
        .where((i) => i.fecha.month == m)
        .toList();

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
      if (!gig.facturable && gig.status == GigStatus.cobradoB) {
        cobradoEnBMes += gig.cachet ?? 0;
      }
    }

    double sinFacturarMes = 0;
    for (final gig in gigsMonth) {
      if (gig.facturable &&
          gig.status == GigStatus.confirmado) {
        sinFacturarMes += gig.cachet ?? 0;
      }
    }

    porMes.add(
      MonthlyFinancialStats(
        month: m,
        pendienteCobrar: pendienteMes,
        cobrado: cobradoMes,
        estimado: cobradoMes + pendienteMes + sinFacturarMes,
        cobradoEnB: cobradoEnBMes,
      ),
    );
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
  final int quarter; // 1-4
  final int year;
  final double ivaAcumulado;
  final DateTime declarationDate;
  final int daysRemaining;
  final String quarterLabel; // "T2 · abril — junio 2026"

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
  '',
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

final quarterlyVatProvider = FutureProvider<QuarterlyVat>((ref) async {
  final now = DateTime.now();
  final quarter = PeriodUtils.currentQuarter(now);
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
    case 1:
      declDate = DateTime(now.year, 4, 20);
      break;
    case 2:
      declDate = DateTime(now.year, 7, 20);
      break;
    case 3:
      declDate = DateTime(now.year, 10, 20);
      break;
    case 4:
      declDate = DateTime(now.year + 1, 1, 30);
      break;
  }

  final daysLeft = declDate
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;

  final label =
      'T$quarter · ${_monthNames[startMonth]} — ${_monthNames[endMonth]} ${now.year}';

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

  final enviadas = allInvoices
      .where((i) => i.status == InvoiceStatus.enviada)
      .toList();
  final overdue = <OverdueInvoice>[];

  for (final inv in enviadas) {
    final days = now.difference(inv.fecha).inDays;
    if (days > 7) {
      final client = await ref.read(clientByIdProvider(inv.clientId).future);
      overdue.add(
        OverdueInvoice(
          invoice: inv,
          clientName: client?.displayName ?? 'Cliente desconocido',
          daysSinceSent: days,
        ),
      );
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
  final sorted = [...allGigs]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final lastGig = sorted.first;
  final lastDate = DateTime(
    lastGig.createdAt.year,
    lastGig.createdAt.month,
    lastGig.createdAt.day,
  );

  return ActivityStreak(daysSinceLastGig: today.difference(lastDate).inDays);
});

// ==================== FINANCIAL SUMMARY PERIOD ====================

final financialPeriodProvider = StateProvider<DashboardPeriod>((ref) {
  final now = DateTime.now();
  return DashboardPeriod(
    mode: DashboardPeriodMode.anio,
    year: now.year,
    month: now.month,
    quarter: PeriodUtils.currentQuarter(now),
  );
});

/// Detailed financial summary for any period, used by the financial summary screen.
class FinancialPeriodSummary {
  final DashboardPeriod period;
  final double cobradoFacturas;
  final double cobradoHistorico; // bolos facturables cobrados sin factura
  final int cobradoHistoricoCount;
  final double cobradoEnB;
  final double pendiente; // solo facturas enviadas
  final int pendienteCount;
  final double previsto; // bolos futuros facturables
  final int previstoCount;
  final double pendienteEnB;
  final int pendienteEnBCount;
  final double previstoEnB;
  final int previstoEnBCount;
  final double ivaTotal;
  final double ivaHistoricoEstimado;
  final int numBolos;
  final int numFacturasPagadas;
  // Sub-period breakdown
  final List<SubPeriodStats> subPeriods;
  // IVA breakdown per quarter (for trimestre/anio modes)
  final List<QuarterVatDetail> ivaQuarters;
  // Comparison with previous period
  final double? prevCobradoTotal;
  final String? prevLabel;

  FinancialPeriodSummary({
    required this.period,
    this.cobradoFacturas = 0,
    this.cobradoHistorico = 0,
    this.cobradoHistoricoCount = 0,
    this.cobradoEnB = 0,
    this.pendiente = 0,
    this.pendienteCount = 0,
    this.previsto = 0,
    this.previstoCount = 0,
    this.pendienteEnB = 0,
    this.pendienteEnBCount = 0,
    this.previstoEnB = 0,
    this.previstoEnBCount = 0,
    this.ivaTotal = 0,
    this.ivaHistoricoEstimado = 0,
    this.numBolos = 0,
    this.numFacturasPagadas = 0,
    this.subPeriods = const [],
    this.ivaQuarters = const [],
    this.prevCobradoTotal,
    this.prevLabel,
  });

  double get cobradoOficial => cobradoFacturas + cobradoHistorico;
  double get cobrado => cobradoOficial + cobradoEnB;
  double get acumulado => cobradoOficial + pendiente;
  double get totalPrevisto => acumulado + previsto;
  double get acumuladoEnB => cobradoEnB + pendienteEnB;
  double get totalPrevistoEnB => acumuladoEnB + previstoEnB;
  double get pendienteTotal => pendiente + pendienteEnB;
  double get previstoTotal => previsto + previstoEnB;
  double get acumuladoTotal => cobrado + pendienteTotal;
  double get totalPrevistoGlobal => acumuladoTotal + previstoTotal;
}

class SubPeriodStats {
  final String label; // "Ene", "T1", etc.
  final int index; // month 1-12 or quarter 1-4
  final double cobrado;
  final double cobradoHistorico; // bolos facturables cobrados sin factura
  final double pendiente;
  final double cobradoEnB;
  final double pendienteEnB;
  final double previstoEnB;
  final double previsto;
  final int numBolos;
  final List<MonthlyGigDetail> gigs;

  SubPeriodStats({
    required this.label,
    required this.index,
    this.cobrado = 0,
    this.cobradoHistorico = 0,
    this.pendiente = 0,
    this.cobradoEnB = 0,
    this.pendienteEnB = 0,
    this.previstoEnB = 0,
    this.previsto = 0,
    this.numBolos = 0,
    this.gigs = const [],
  });

  double get cobradoOficial => cobrado + cobradoHistorico;
  double get total => cobradoOficial + cobradoEnB;
  double get acumulado => cobradoOficial + pendiente;
  double get acumuladoTotal => total + pendiente + pendienteEnB;
  double get totalPrevisto => acumulado + previsto;
  double get totalPrevistoGlobal => acumuladoTotal + previsto + previstoEnB;
  bool get hasData =>
      cobrado > 0 ||
      pendiente > 0 ||
      cobradoEnB > 0 ||
      pendienteEnB > 0 ||
      previsto > 0 ||
      previstoEnB > 0;
}

const _shortMonths = [
  'Ene',
  'Feb',
  'Mar',
  'Abr',
  'May',
  'Jun',
  'Jul',
  'Ago',
  'Sep',
  'Oct',
  'Nov',
  'Dic',
];

final financialPeriodSummaryProvider =
    FutureProvider.family<FinancialPeriodSummary, DashboardPeriod>((
      ref,
      period,
    ) async {
      final allGigs = await ref.watch(gigsProvider.future);
      final allInvoices = await ref.watch(invoicesProvider.future);

      final stats = _calcPeriodStats(period, allGigs, allInvoices);

      // Count invoices
      final (start, end) = _periodRange(period);
      final invoicesInPeriod = allInvoices
          .where((i) => !i.fecha.isBefore(start) && !i.fecha.isAfter(end))
          .toList();
      int numPagadas = invoicesInPeriod
          .where((i) => i.status == InvoiceStatus.pagada)
          .length;

      // IVA quarters (only for trimestre and anio modes)
      List<QuarterVatDetail> ivaQuarters = [];
      if (period.mode == DashboardPeriodMode.trimestre ||
          period.mode == DashboardPeriodMode.anio) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final currentQuarter = PeriodUtils.currentQuarter(now);

        // Load declared quarters
        final declaredSet = await ref.watch(declaredQuartersProvider.future);

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

          // Facturas pagadas del trimestre
          final qInvoices = allInvoices
              .where(
                (inv) =>
                    inv.fecha.year == period.year &&
                    inv.fecha.month >= sM &&
                    inv.fecha.month <= eM &&
                    inv.status == InvoiceStatus.pagada,
              )
              .toList();

          double ivaFacturas = 0;
          final invoiceDetails = <QuarterVatInvoice>[];
          for (final inv in qInvoices) {
            ivaFacturas += inv.ivaAmount;
            final client = await ref.read(
              clientByIdProvider(inv.clientId).future,
            );
            invoiceDetails.add(
              QuarterVatInvoice(
                invoiceId: inv.id,
                numero: inv.numero,
                clientName: client?.displayName ?? 'Cliente desconocido',
                fecha: inv.fecha,
                base: inv.subtotal,
                iva: inv.ivaAmount,
              ),
            );
          }

          // Bolos históricos facturables cobrados sin factura en este trimestre
          final qHistoricGigs = allGigs
              .where(
                (g) =>
                    g.fecha.year == period.year &&
                    g.fecha.month >= sM &&
                    g.fecha.month <= eM &&
                    g.facturable &&
                    g.status == GigStatus.cobrado &&
                    (g.invoiceId == null || g.invoiceId!.isEmpty),
              )
              .toList();

          double baseHistorico = 0;
          for (final gig in qHistoricGigs) {
            baseHistorico += (gig.cachet ?? 0);
          }
          final ivaHistorico = baseHistorico > 0
              ? baseHistorico / 1.21 * 0.21
              : 0.0;
          final isEstimated = ivaHistorico > 0;

          final ivaTotal = ivaFacturas + ivaHistorico;

          final declDate = _declarationDate(q, period.year);
          final daysLeft = declDate.difference(today).inDays;

          // Check if manually declared
          final isDeclared = declaredSet.contains('${period.year}-$q');

          String status;
          if (isDeclared) {
            status = 'declarado';
          } else if (period.year < now.year ||
              (period.year == now.year && q < currentQuarter)) {
            status = daysLeft < 0 && ivaTotal > 0
                ? 'pendiente_declarar'
                : 'pasado';
          } else if (period.year == now.year && q == currentQuarter) {
            status = 'en_curso';
          } else {
            status = 'proximo';
          }

          ivaQuarters.add(
            QuarterVatDetail(
              quarter: q,
              year: period.year,
              ivaTotal: ivaTotal,
              ivaFacturas: ivaFacturas,
              ivaHistoricoEstimado: ivaHistorico,
              isEstimated: isEstimated,
              isDeclared: isDeclared,
              declarationDate: declDate,
              daysRemaining: daysLeft,
              status: status,
              invoices: invoiceDetails,
            ),
          );
        }
      }

      // Sub-periods
      List<SubPeriodStats> subPeriods = [];
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      Future<List<SubPeriodStats>> buildMonthlySubPeriods(
        List<int> months,
      ) async {
        final result = <SubPeriodStats>[];
        for (final m in months) {
          final mGigs = allGigs
              .where(
                (g) =>
                    g.fecha.year == period.year &&
                    g.fecha.month == m &&
                    g.status != GigStatus.cancelado,
              )
              .toList();
          final mInvoices = allInvoices
              .where((i) => i.fecha.year == period.year && i.fecha.month == m)
              .toList();

          double cobrado = 0,
              pendiente = 0,
              enB = 0,
              pendienteEnB = 0,
              previstoEnB = 0,
              previsto = 0,
              cobradoHist = 0;
          for (final inv in mInvoices) {
            if (inv.status == InvoiceStatus.pagada) {
              cobrado += inv.total;
            } else if (inv.status == InvoiceStatus.enviada) {
              pendiente += inv.total;
            }
          }
          for (final gig in mGigs) {
            final cachet = gig.cachet ?? 0;
            final gigDate = DateTime(
              gig.fecha.year,
              gig.fecha.month,
              gig.fecha.day,
            );
            // Bolos históricos facturables cobrados sin factura
            if (gig.facturable &&
                gig.status == GigStatus.cobrado &&
                (gig.invoiceId == null || gig.invoiceId!.isEmpty)) {
              cobradoHist += cachet;
            }
            if (gig.facturable &&
                !gigDate.isBefore(today) &&
                gig.status == GigStatus.confirmado) {
              previsto += cachet;
            }
            if (!gig.facturable) {
              if (gig.status == GigStatus.cobradoB) {
                enB += cachet;
              } else if (gig.status == GigStatus.realizadoB) {
                pendienteEnB += cachet;
              } else if (gig.status == GigStatus.confirmadoB) {
                previstoEnB += cachet;
              }
            }
          }

          final gigDetails = <MonthlyGigDetail>[];
          for (final gig in mGigs) {
            final client = await ref.read(
              clientByIdProvider(gig.clientId).future,
            );
            gigDetails.add(
              MonthlyGigDetail(
                gigId: gig.id,
                clientName: client?.displayName ?? 'Desconocido',
                fecha: gig.fecha,
                importe: gig.cachet ?? 0,
                status: gig.status,
              ),
            );
          }

          result.add(
            SubPeriodStats(
              label: _shortMonths[m - 1],
              index: m,
              cobrado: cobrado,
              cobradoHistorico: cobradoHist,
              pendiente: pendiente,
              cobradoEnB: enB,
              pendienteEnB: pendienteEnB,
              previstoEnB: previstoEnB,
              previsto: previsto,
              numBolos: mGigs.length,
              gigs: gigDetails,
            ),
          );
        }
        return result;
      }

      if (period.mode == DashboardPeriodMode.anio) {
        subPeriods = await buildMonthlySubPeriods(
          List.generate(12, (i) => i + 1),
        );
      } else if (period.mode == DashboardPeriodMode.trimestre) {
        final startM = (period.quarter - 1) * 3 + 1;
        subPeriods = await buildMonthlySubPeriods([
          startM,
          startM + 1,
          startM + 2,
        ]);
      }
      // Month mode: no sub-periods, but include gigs
      if (period.mode == DashboardPeriodMode.mes) {
        final mGigs = allGigs
            .where(
              (g) =>
                  g.fecha.year == period.year &&
                  g.fecha.month == period.month &&
                  g.status != GigStatus.cancelado,
            )
            .toList();

        final gigDetails = <MonthlyGigDetail>[];
        for (final gig in mGigs) {
          final client = await ref.read(
            clientByIdProvider(gig.clientId).future,
          );
          gigDetails.add(
            MonthlyGigDetail(
              gigId: gig.id,
              clientName: client?.displayName ?? 'Desconocido',
              fecha: gig.fecha,
              importe: gig.cachet ?? 0,
              status: gig.status,
            ),
          );
        }

        subPeriods.add(
          SubPeriodStats(
            label: _shortMonths[period.month - 1],
            index: period.month,
            cobrado: stats.cobradoFacturas,
            cobradoHistorico: stats.cobradoHistorico,
            pendiente: stats.pendiente,
            cobradoEnB: stats.cobradoEnB,
            pendienteEnB: stats.pendienteEnB,
            previstoEnB: stats.previstoEnB,
            previsto: stats.previsto,
            numBolos: stats.totalBolos,
            gigs: gigDetails,
          ),
        );
      }

      // Previous period comparison
      final prev = period.previous;
      final prevStats = _calcPeriodStats(prev, allGigs, allInvoices);
      final hasPrev = prevStats.cobrado > 0;

      return FinancialPeriodSummary(
        period: period,
        cobradoFacturas: stats.cobradoFacturas,
        cobradoHistorico: stats.cobradoHistorico,
        cobradoHistoricoCount: stats.cobradoHistoricoCount,
        cobradoEnB: stats.cobradoEnB,
        pendiente: stats.pendiente,
        pendienteCount: stats.pendienteCount,
        previsto: stats.previsto,
        previstoCount: stats.previstoCount,
        pendienteEnB: stats.pendienteEnB,
        pendienteEnBCount: stats.pendienteEnBCount,
        previstoEnB: stats.previstoEnB,
        previstoEnBCount: stats.previstoEnBCount,
        ivaTotal: stats.ivaAcumulado,
        ivaHistoricoEstimado: stats.ivaHistoricoEstimado,
        numBolos: stats.totalBolos,
        numFacturasPagadas: numPagadas,
        subPeriods: subPeriods,
        ivaQuarters: ivaQuarters,
        prevCobradoTotal: hasPrev ? prevStats.cobrado : null,
        prevLabel: hasPrev ? prev.label : null,
      );
    });
