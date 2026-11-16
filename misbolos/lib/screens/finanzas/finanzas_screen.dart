import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _FinanzasScreenState extends ConsumerState<FinanzasScreen> {
  TabController? _tabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.maybeOf(context);
    if (controller == null || identical(controller, _tabController)) return;

    _tabController?.removeListener(_onTabChanged);
    _tabController = controller;
    _tabController?.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    final controller = _tabController;
    if (controller == null) return;
    if (controller.indexIsChanging) return;
    ref.read(finanzasTabProvider.notifier).state = controller.index;
    if (controller.index != 0) return;
    unawaited(
      ref
          .read(invoicesProvider.notifier)
          .refreshFromCloud(reason: 'finanzas_tab_facturas'),
    );
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    // Facturas y Gastos tienen tour; Clientes no.
    final pestana = ref.watch(finanzasTabProvider);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const SafeArea(bottom: false, child: SizedBox(height: 12)),
          Material(
            color: colors.surface,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
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
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                InvoicesListScreen(),
                GastosInversionesScreen(),
                ClientsListScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
