import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../providers/invoice_provider.dart';
import '../invoices/invoices_list_screen.dart';
import '../expenses/expenses_screen.dart';
import '../assets/assets_screen.dart';
import '../clients/clients_list_screen.dart';

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
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const SafeArea(bottom: false, child: SizedBox(height: 12)),
          Material(
            color: colors.surface,
            child: TabBar(
              labelColor: scheme.primary,
              unselectedLabelColor: colors.textSecondary,
              indicatorColor: scheme.primary,
              indicatorWeight: 3,
              tabs: const [
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Facturas'),
                Tab(icon: Icon(Icons.euro_outlined), text: 'Gastos'),
                Tab(
                  icon: Icon(Icons.inventory_2_outlined),
                  text: 'Inversiones',
                ),
                Tab(icon: Icon(Icons.people_outline), text: 'Clientes'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                InvoicesListScreen(),
                ExpensesScreen(),
                AssetsScreen(),
                ClientsListScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
