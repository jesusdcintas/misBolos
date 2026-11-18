import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../providers/invoice_provider.dart';
import '../invoices/invoices_list_screen.dart';
import 'gastos_inversiones_screen.dart';
import '../clients/clients_list_screen.dart';
import '../../core/services/estado_tutorial.dart';
import '../../widgets/tutorial/boton_ayuda_tour.dart';

/// Qué pestaña de Finanzas se está viendo. La usan los tours de Facturas y de
/// Gastos, que no deben saltar hasta que su pestaña esté a la vista.
final finanzasTabProvider = StateProvider<int>((ref) => 0);

class FinanzasScreen extends ConsumerStatefulWidget {
  const FinanzasScreen({super.key});

  @override
  ConsumerState<FinanzasScreen> createState() => _FinanzasScreenState();
}

class _FinanzasScreenState extends ConsumerState<FinanzasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _pestanaInicialAplicada = false;

  @override
  void initState() {
    super.initState();
    // El controlador es nuestro: así la pestaña inicial y el aviso de cambio
    // funcionan siempre. (Con DefaultTabController, el controlador quedaba por
    // debajo y este State no llegaba a verlo.)
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pestanaInicialAplicada) return;
    _pestanaInicialAplicada = true;
    // La guía manda a Gastos con ?tab=gastos; la barra de abajo entra sin
    // parámetro y se queda en Facturas.
    final inicial = switch (
      GoRouterState.of(context).uri.queryParameters['tab']
    ) {
      'gastos' => 1,
      'clientes' => 2,
      _ => 0,
    };
    // Mover la pestaña sin disparar el oyente: tocar el provider aquí, en mitad
    // del build, lanzaría un error de Riverpod.
    if (_tabController.index != inicial) {
      _tabController.removeListener(_onTabChanged);
      _tabController.index = inicial;
      _tabController.addListener(_onTabChanged);
    }
    // Deja el provider en la pestaña de arranque para que el tour de Gastos,
    // que espera a verse su pestaña, sepa desde el primer momento cuál es.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(finanzasTabProvider.notifier).state = inicial;
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    ref.read(finanzasTabProvider.notifier).state = _tabController.index;
    if (_tabController.index != 0) return;
    unawaited(
      ref
          .read(invoicesProvider.notifier)
          .refreshFromCloud(reason: 'finanzas_tab_facturas'),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    // Facturas y Gastos tienen tour; Clientes no.
    final pestana = ref.watch(finanzasTabProvider);
    return Column(
      children: [
        const SafeArea(bottom: false, child: SizedBox(height: 12)),
        Material(
          color: colors.surface,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  labelColor: scheme.primary,
                  unselectedLabelColor: colors.textSecondary,
                  indicatorColor: scheme.primary,
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.receipt_long_outlined),
                      text: 'Facturas',
                    ),
                    Tab(
                      icon: Icon(Icons.euro_outlined),
                      text: 'Gastos e Inversiones',
                    ),
                    Tab(icon: Icon(Icons.people_outline), text: 'Clientes'),
                  ],
                ),
              ),
              if (pestana == 0)
                BotonAyudaTour(tour: Tour.facturas, pasos: pasosTourFacturas)
              else if (pestana == 1)
                BotonAyudaTour(tour: Tour.gastos, pasos: pasosTourGastos),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              InvoicesListScreen(),
              GastosInversionesScreen(),
              ClientsListScreen(embedded: true),
            ],
          ),
        ),
      ],
    );
  }
}
