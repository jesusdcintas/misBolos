import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'providers/sync_provider.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/calendar/calendar_screen.dart';
import 'screens/calendar/gig_detail_screen.dart';
import 'screens/calendar/gig_form_screen.dart';
import 'screens/clients/clients_list_screen.dart';
import 'screens/clients/client_detail_screen.dart';
import 'screens/clients/client_form_screen.dart';
import 'screens/invoices/invoices_list_screen.dart';
import 'screens/invoices/invoice_detail_screen.dart';
import 'screens/invoices/invoice_preview_screen.dart';
import 'screens/invoices/invoice_form_screen.dart';
import 'screens/stats/stats_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/dashboard/financial_summary_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/expenses/expenses_screen.dart';
import 'screens/expenses/expense_form_screen.dart';
import 'screens/expenses/expense_detail_screen.dart';
import 'screens/assets/assets_screen.dart';
import 'screens/assets/asset_form_screen.dart';
import 'screens/assets/asset_detail_screen.dart';

Page<void> _slideUpPage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondary, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
  );
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => _ScaffoldWithNavBar(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const DashboardScreen(),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/calendar',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const CalendarScreen(),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/clients',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ClientsListScreen(),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/invoices',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const InvoicesListScreen(),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ProfileScreen(),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/expenses',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ExpensesScreen(),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/assets',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const AssetsScreen(),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/settings',
        pageBuilder: (context, state) => _slideUpPage(const SettingsScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/stats',
        pageBuilder: (context, state) => _slideUpPage(const StatsScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/financial',
        pageBuilder: (context, state) => _slideUpPage(const FinancialSummaryScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/gig/new',
        pageBuilder: (context, state) => _slideUpPage(const GigFormScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/gig/edit/:id',
        pageBuilder: (context, state) => _slideUpPage(
          GigFormScreen(gigId: state.pathParameters['id']),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/gig/:id',
        pageBuilder: (context, state) => _slideUpPage(
          GigDetailScreen(gigId: state.pathParameters['id']!),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/client/new',
        pageBuilder: (context, state) => _slideUpPage(const ClientFormScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/client/edit/:id',
        pageBuilder: (context, state) => _slideUpPage(
          ClientFormScreen(clientId: state.pathParameters['id']),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/client/:id',
        pageBuilder: (context, state) => _slideUpPage(
          ClientDetailScreen(clientId: state.pathParameters['id']!),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/invoice/:id',
        pageBuilder: (context, state) => _slideUpPage(
          InvoiceDetailScreen(invoiceId: state.pathParameters['id']!),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/invoice/preview/:id',
        pageBuilder: (context, state) => _slideUpPage(
          InvoicePreviewScreen(invoiceId: state.pathParameters['id']!),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/invoice/edit/:id',
        pageBuilder: (context, state) => _slideUpPage(
          InvoiceFormScreen(invoiceId: state.pathParameters['id']!),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/invoice/new/:gigId',
        pageBuilder: (context, state) => _slideUpPage(
          InvoiceFormScreen(gigId: state.pathParameters['gigId']!),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/expense/new',
        pageBuilder: (context, state) =>
            _slideUpPage(const ExpenseFormScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/expense/edit/:id',
        pageBuilder: (context, state) => _slideUpPage(
          ExpenseFormScreen(
              expenseId: int.parse(state.pathParameters['id']!)),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/expense/:id',
        pageBuilder: (context, state) => _slideUpPage(
          ExpenseDetailScreen(
              expenseId: int.parse(state.pathParameters['id']!)),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/asset/new',
        pageBuilder: (context, state) =>
            _slideUpPage(const AssetFormScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/asset/edit/:id',
        pageBuilder: (context, state) => _slideUpPage(
          AssetFormScreen(
              assetId: int.parse(state.pathParameters['id']!)),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/asset/:id',
        pageBuilder: (context, state) => _slideUpPage(
          AssetDetailScreen(
              assetId: int.parse(state.pathParameters['id']!)),
          state,
        ),
      ),
    ],
  );
});

class MisBolosApp extends ConsumerStatefulWidget {
  const MisBolosApp({super.key});

  @override
  ConsumerState<MisBolosApp> createState() => _MisBolosAppState();
}

class _MisBolosAppState extends ConsumerState<MisBolosApp> {
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _autoSync();
  }

  Future<void> _autoSync() async {
    if (_synced) return;
    _synced = true;
    // Esperar un momento para que Supabase se inicialice
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final notifier = ref.read(syncProvider.notifier);
    if (notifier.isAuthenticated) {
      await notifier.syncAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MisBolos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      routerConfig: router,
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

class _ScaffoldWithNavBar extends StatefulWidget {
  final Widget child;
  const _ScaffoldWithNavBar({required this.child});

  @override
  State<_ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<_ScaffoldWithNavBar> {
  late final PageController _pageController;

  static const _paths = ['/', '/calendar', '/clients', '/invoices', '/expenses', '/assets', '/profile'];

  static int _indexFromLocation(String location) {
    if (location == '/') return 0;
    if (location.startsWith('/calendar')) return 1;
    if (location.startsWith('/clients')) return 2;
    if (location.startsWith('/invoices')) return 3;
    if (location.startsWith('/expenses')) return 4;
    if (location.startsWith('/assets')) return 5;
    if (location.startsWith('/profile')) return 6;
    return 0;
  }

  int _currentIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newIndex = _indexFromLocation(GoRouterState.of(context).uri.path);
    if (newIndex != _currentIndex) {
      _currentIndex = newIndex;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(newIndex);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (index != _currentIndex) {
      HapticFeedback.selectionClick();
      _currentIndex = index;
      context.go(_paths[index]);
    }
  }

  void _onNavTapped(int index) {
    HapticFeedback.selectionClick();
    if (index == _currentIndex) return;
    _currentIndex = index;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    context.go(_paths[index]);
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _indexFromLocation(GoRouterState.of(context).uri.path);

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: const [
          DashboardScreen(),
          CalendarScreen(),
          ClientsListScreen(),
          InvoicesListScreen(),
          ExpensesScreen(),
          AssetsScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: _onNavTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outlined),
            selectedIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Facturas',
          ),
          NavigationDestination(
            icon: Icon(Icons.euro_outlined),
            selectedIcon: Icon(Icons.euro),
            label: 'Gastos',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inversiones',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Mi Perfil',
          ),
        ],
      ),
    );
  }
}
