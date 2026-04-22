import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../invoices/invoices_list_screen.dart';
import '../expenses/expenses_screen.dart';
import '../assets/assets_screen.dart';

class FinanzasScreen extends StatelessWidget {
  const FinanzasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: AppColors.primary,
            child: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              tabs: const [
                Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Facturas'),
                Tab(icon: Icon(Icons.euro_outlined), text: 'Gastos'),
                Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Inversiones'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                InvoicesListScreen(),
                ExpensesScreen(),
                AssetsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
