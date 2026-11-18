import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/client.dart';
import '../../models/gig.dart';
import '../../providers/client_provider.dart';
import '../../providers/financial_summary_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/common/dismissible_alert_banner.dart';
import '../../widgets/common/dj_refresh_indicator.dart';
import '../../widgets/common/expandable_fab.dart';
import '../../widgets/common/gig_card_content.dart';
import '../../widgets/common/skeleton_loading.dart';
import '../../widgets/dashboard/income_period_card.dart';
import '../../widgets/dashboard/pending_invoices_card.dart';
import '../../widgets/dashboard/period_selector.dart';
import '../../widgets/dashboard/taxes_period_card.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/tirar_para_sincronizar.dart';
import '../../core/services/estado_tutorial.dart';
import '../../widgets/common/acciones_bolo.dart';
import '../../widgets/common/menu_acciones.dart';
import '../../widgets/tutorial/boton_ayuda_tour.dart';
import '../../widgets/tutorial/lanzador_tour.dart';
import '../../widgets/tutorial/tour.dart';
import '../../core/services/guia_inicio.dart';
import '../../core/services/google_drive_service.dart';
import '../../providers/guia_inicio_provider.dart';
import '../../widgets/invoices/proxima_factura.dart';
import '../../screens/settings/import_screen.dart';
import '../../widgets/tutorial/cierre_guia.dart';
import '../../widgets/tutorial/tarjeta_guia_inicio.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tutorial_provider.dart';

/// Ancho a partir del cual las secciones se reparten en dos columnas. Es el
/// mismo corte que usa la pantalla de Ajustes.
const double _anchoDosColumnas = 700;

final _claveTourPeriodo = GlobalKey();
final _claveTourIngresos = GlobalKey();
final _claveTourImpuestos = GlobalKey();
final _claveTourAnadir = GlobalKey();

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardPeriodProvider);
    final statsAsync = ref.watch(periodDashboardStatsProvider(period));
    final fiscalAsync = ref.watch(financialSummaryProvider(period));
    final upcomingAsync = ref.watch(upcomingGigsProvider);
    final pendingAsync = ref.watch(pendingInvoicesProvider);
    final overdueAsync = ref.watch(overdueInvoicesProvider);

    final pantalla = Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.dashboard),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Resumen Financiero',
            onPressed: () => context.push('/financial'),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Estadísticas',
            onPressed: () => context.push('/stats'),
          ),
          BotonAyudaTour(
            tour: Tour.inicio,
            pasos: () => pasosDeInicio(
              periodo: _claveTourPeriodo,
              ingresos: _claveTourIngresos,
              impuestos: _claveTourImpuestos,
              anadir: _claveTourAnadir,
            ),
          ),
        ],
      ),
      body: DJRefreshIndicator(
        onRefresh: () async {
          await sincronizarTirando(context, ref);
          ref.invalidate(periodDashboardStatsProvider(period));
          ref.invalidate(financialSummaryProvider(period));
          ref.invalidate(upcomingGigsProvider);
          ref.invalidate(pendingInvoicesProvider);
          ref.invalidate(overdueInvoicesProvider);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dosColumnas = constraints.maxWidth >= _anchoDosColumnas;

            final ingresos = statsAsync.when(
              // El periodo se cambia con las flechas del selector: deslizar
              // aquí se comía gestos de la lista y confundía más que ayudaba.
              data: (stats) => KeyedSubtree(
                key: _claveTourIngresos,
                child: IncomePeriodCard(stats: stats, period: period),
              ),
              loading: () => const DashboardSkeleton(),
              error: (e, _) => Text('Error: $e'),
            );

            final impuestos = fiscalAsync.when(
              data: (summary) => KeyedSubtree(
                key: _claveTourImpuestos,
                child: TaxesPeriodCard(summary: summary, period: period),
              ),
              loading: () => const DashboardSkeleton(),
              error: (e, _) => Text('Error: $e'),
            );

            final proximos = upcomingAsync.when(
              data: (upcoming) => _UpcomingGigs(upcoming: upcoming),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );

            final pendientes = pendingAsync.when(
              data: (lista) => PendingInvoicesCard(pendientes: lista),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _GuiaInicio(),
                KeyedSubtree(
                  key: _claveTourPeriodo,
                  child: const PeriodSelector(),
                ),
                const SizedBox(height: 16),

                // Aviso de impagos: es global, no sigue el periodo.
                overdueAsync.when(
                  data: (alert) {
                    if (alert.invoices.isEmpty) return const SizedBox.shrink();
                    return DismissibleAlertBanner(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _OverdueBanner(alert: alert),
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                _DosColumnas(
                  activo: dosColumnas,
                  // Ingresos e impuestos se leen como un par: en dos columnas
                  // la más baja se estira hasta la altura de la otra.
                  igualarAltura: true,
                  izquierda: ingresos,
                  derecha: impuestos,
                ),
                const SizedBox(height: 24),

                _DosColumnas(
                  activo: dosColumnas,
                  izquierda: proximos,
                  derecha: pendientes,
                ),
                const SizedBox(height: 24),

                OutlinedButton.icon(
                  onPressed: () => context.push('/stats'),
                  icon: const Icon(Icons.bar_chart, size: 18),
                  label: const Text('Ver todas las métricas'),
                ),
                const SizedBox(height: 16),

                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
      floatingActionButton: KeyedSubtree(
        key: _claveTourAnadir,
        child: ExpandableFAB(
          actions: [
            FABAction(
              icon: Icons.music_note,
              label: 'Nuevo bolo',
              color: context.colors.accentSoft,
              onTap: (ctx) => ctx.push('/gig/new'),
            ),
            FABAction(
              icon: Icons.person_add,
              label: 'Nuevo cliente',
              color: context.colors.purple,
              onTap: (ctx) => ctx.push('/client/new'),
            ),
            FABAction(
              icon: Icons.euro_outlined,
              label: 'Nuevo gasto o inversión',
              color: context.colors.warning,
              onTap: (ctx) => ctx.push('/expense/new'),
            ),
          ],
        ),
      ),
    );

    // El tour de Inicio salta la primera vez, con los datos ya cargados.
    return TourPorEncargo(
      tour: Tour.inicio,
      listo: statsAsync.hasValue,
      pasos: () => pasosDeInicio(
        periodo: _claveTourPeriodo,
        ingresos: _claveTourIngresos,
        impuestos: _claveTourImpuestos,
        anadir: _claveTourAnadir,
      ),
      child: pantalla,
    );
  }
}

/// La guía de inicio, enganchada a los datos de verdad.
///
/// Lleva al usuario nuevo por el flujo real, en orden. Quien ya usaba la app
/// no la ve nunca: de eso se encarga el estado del tutorial.
class _GuiaInicio extends ConsumerStatefulWidget {
  const _GuiaInicio();

  @override
  ConsumerState<_GuiaInicio> createState() => _GuiaInicioState();
}

class _GuiaInicioState extends ConsumerState<_GuiaInicio> {
  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(guiaVisibleProvider);
    final pasos = ref.watch(guiaInicioProvider);

    // Avisar cuando un paso se completa, con el siguiente a mano.
    ref.listen<List<EstadoPasoGuia>>(guiaInicioProvider, (antes, ahora) {
      if (antes == null || !visible) return;
      for (final estado in ahora) {
        final anterior = antes.firstWhere(
          (p) => p.paso == estado.paso,
          orElse: () => estado,
        );
        if (estado.hecho && !anterior.hecho) {
          _avisarPasoCompletado(estado.paso, ahora);
          break;
        }
      }
    });

    if (!visible) return const SizedBox.shrink();
    if (guiaTerminada(pasos)) {
      return CierreGuia(
        alOcultar: () => ref.read(tutorialProvider.notifier).ocultarTarjeta(),
      );
    }

    return TarjetaGuiaInicio(
      pasos: pasos,
      siguiente: siguientePaso(pasos),
      alHacerlo: _hacerPaso,
      alSaltar: (paso) => ref.read(tutorialProvider.notifier).saltarPaso(paso),
      alOcultar: () => ref.read(tutorialProvider.notifier).ocultarTarjeta(),
      alImportar: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
    );
  }

  void _avisarPasoCompletado(PasoGuia hecho, List<EstadoPasoGuia> pasos) {
    final siguiente = siguientePaso(pasos);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 8),
        content: Text(
          siguiente == null
              ? 'Paso completado · Ya está todo'
              : 'Paso completado · Siguiente: ${siguiente.titulo}',
        ),
        action: hecho == PasoGuia.carpetas
            ? SnackBarAction(label: 'Abrir Drive', onPressed: _abrirDrive)
            : siguiente == null
            ? null
            : SnackBarAction(
                label: 'Continuar',
                onPressed: () => _hacerPaso(siguiente),
              ),
      ),
    );
  }

  Future<void> _abrirDrive() async {
    final settings = await ref.read(settingsProvider.future);
    final raiz = settings.driveRootFolderId?.trim();
    if (!mounted) return;
    if (raiz == null || raiz.isEmpty) {
      _avisar('Todavía no has elegido carpeta de trabajo en Drive.');
      return;
    }
    try {
      await GoogleDriveService.instance.openFolder(raiz);
    } catch (e) {
      if (mounted) _avisar('No se pudo abrir Drive: $e');
    }
  }

  void _avisar(String mensaje, {SnackBarAction? accion}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        action: accion,
        persist: false,
        duration: Duration(seconds: accion == null ? 5 : 8),
      ),
    );
  }

  Future<void> _hacerPaso(PasoGuia paso) async {
    // El del número de factura se resuelve aquí mismo, con una pregunta.
    if (paso == PasoGuia.numeracion) {
      await _preguntarPorLaNumeracion();
      return;
    }

    final destino = destinoDelPaso(
      paso,
      boloSinFacturaId: ref.read(boloSinFacturaProvider),
      facturaRecienteId: ref.read(facturaRecienteProvider),
    );

    // Crear una factura no es un ensayo: conviene decirlo antes.
    if (paso == PasoGuia.factura && destino.aviso == null) {
      final sigue = await _confirmarFacturaReal();
      if (!sigue || !mounted) return;
    }

    await ref.read(tutorialProvider.notifier).encargarTour(destino.tour);
    if (!mounted) return;

    if (destino.aviso != null) _avisar(destino.aviso!);
    // Las pestañas se cambian; lo demás se abre encima.
    if (destino.ruta == '/calendar' || destino.ruta == '/finanzas') {
      context.go(destino.ruta);
    } else {
      context.push(destino.ruta);
    }
  }

  Future<bool> _confirmarFacturaReal() async {
    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vas a crear una factura de verdad'),
        content: const Text(
          'Esta factura es real y tendrá número. Si solo quieres probar, al '
          'final de la guía te enseñamos a borrarla para que la numeración '
          'vuelva atrás.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    return seguir == true;
  }

  Future<void> _preguntarPorLaNumeracion() async {
    final yaFacturaba = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tu próxima factura'),
        content: const Text(
          '¿Ya has emitido facturas este año fuera de MisBolos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, empiezo de cero'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, ya he facturado'),
          ),
        ],
      ),
    );
    if (yaFacturaba == null || !mounted) return;

    await ref.read(tutorialProvider.notifier).marcarNumeracionRevisada();
    if (!mounted) return;
    if (yaFacturaba) {
      await mostrarDialogoProximaFactura(context, ref, DateTime.now().year);
    } else {
      _avisar('Perfecto: tu primera factura será la número 1.');
    }
  }
}

/// Dos secciones en fila cuando hay sitio, y una debajo de otra si no.
class _DosColumnas extends StatelessWidget {
  final bool activo;

  /// Las dos columnas comparten la altura de la más alta.
  final bool igualarAltura;
  final Widget izquierda;
  final Widget derecha;

  const _DosColumnas({
    required this.activo,
    this.igualarAltura = false,
    required this.izquierda,
    required this.derecha,
  });

  @override
  Widget build(BuildContext context) {
    if (!activo) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [izquierda, const SizedBox(height: 24), derecha],
      );
    }

    final fila = Row(
      crossAxisAlignment: igualarAltura
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
      children: [
        Expanded(child: izquierda),
        const SizedBox(width: 16),
        Expanded(child: derecha),
      ],
    );

    // stretch necesita una altura concreta, y dentro de un ListView la Row no
    // la tiene: IntrinsicHeight la fija a la del hijo más alto.
    return igualarAltura ? IntrinsicHeight(child: fila) : fila;
  }
}

// ==================== PRÓXIMOS BOLOS ====================

class _UpcomingGigs extends StatelessWidget {
  final List<Gig> upcoming;

  const _UpcomingGigs({required this.upcoming});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final futureGigs = upcoming
        .where((g) {
          final gDate = DateTime(g.fecha.year, g.fecha.month, g.fecha.day);
          return !gDate.isBefore(today);
        })
        .take(3)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Próximos bolos',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/calendar'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Agenda →'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (futureGigs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border, width: 0.6),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.event_available,
                  size: 40,
                  color: colors.textSecondary,
                ),
                const SizedBox(height: 8),
                Text(
                  'No tienes bolos programados',
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => context.push('/gig/new'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Añadir bolo'),
                ),
              ],
            ),
          )
        else
          ...futureGigs.map((gig) {
            final gDate = DateTime(
              gig.fecha.year,
              gig.fecha.month,
              gig.fecha.day,
            );
            final daysLeft = gDate.difference(today).inDays;
            return _UpcomingGigTile(gig: gig, daysLeft: daysLeft);
          }),
      ],
    );
  }
}

// ==================== GIG TILES ====================

class _UpcomingGigTile extends ConsumerWidget {
  final Gig gig;
  final int daysLeft;
  const _UpcomingGigTile({required this.gig, required this.daysLeft});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final primary = Theme.of(context).colorScheme.primary;
    final clientAsync = ref.watch(clientByIdProvider(gig.clientId));

    String badgeText;
    Color badgeBg;
    Color badgeTextColor;
    if (daysLeft == 0) {
      badgeText = 'hoy';
      badgeBg = context.colors.successBg;
      badgeTextColor = context.colors.success;
    } else if (daysLeft == 1) {
      badgeText = 'mañana';
      badgeBg = context.colors.warningBg;
      badgeTextColor = context.colors.warning;
    } else {
      badgeText = 'en $daysLeft días';
      badgeBg = colors.infoBg;
      badgeTextColor = primary;
    }

    return GestoMenuAcciones(
      acciones: () => accionesRapidasDeBolo(
        context,
        ref,
        gig,
        alCancelar: (g) => cancelarBoloConDeshacer(context, ref, g),
      ),
      child: Card(
        // Sin margen horizontal: el del tema (16 px) metía la lista por dentro
        // del título, al contrario que la de pendiente de cobro.
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          onTap: () => context.push('/gig/${gig.id}'),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: gig.facturable ? colors.infoBg : context.colors.purpleBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.music_note_outlined,
              color: gig.facturable ? primary : context.colors.purple,
              size: 22,
            ),
          ),
          title: GigCardContent(
            nombre: clientAsync.when(
              data: (client) => client?.displayName ?? 'Cliente desconocido',
              loading: () => '...',
              error: (_, __) => 'Error',
            ),
            detalle: DateFormatter.display(gig.fecha),
            importe: gig.cachet != null
                ? CurrencyFormatter.format(gig.cachet!)
                : null,
            gig: gig,
            extra: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  fontSize: 11,
                  color: badgeTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// ==================== OVERDUE BANNER ====================

/// Aviso compacto de facturas pendientes de más de 7 días, en una línea.
class _OverdueBanner extends StatelessWidget {
  final OverdueAlert alert;

  const _OverdueBanner({required this.alert});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isRed = alert.hasOver30Days;
    final acento = isRed ? colors.error : colors.warning;
    final fondo = isRed ? colors.errorBg : colors.warningBg;
    final n = alert.invoices.length;

    final String texto;
    if (n == 1) {
      final oi = alert.invoices.first;
      texto =
          '${oi.clientName} te debe '
          '${CurrencyFormatter.format(oi.invoice.total)} desde hace '
          '${oi.daysSinceSent} días';
    } else {
      texto = 'Tienes $n facturas pendientes desde hace más de 7 días';
    }

    return GestureDetector(
      onTap: () => context.go('/finanzas'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: acento, width: 3)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: acento, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: acento,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}
