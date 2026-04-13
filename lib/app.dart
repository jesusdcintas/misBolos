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

class _ScaffoldWithNavBar extends StatelessWidget {
  final Widget child;
  const _ScaffoldWithNavBar({required this.child});

  static int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location == '/') return 0;
    if (location.startsWith('/calendar')) return 1;
    if (location.startsWith('/clients')) return 2;
    if (location.startsWith('/invoices')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              context.go('/calendar');
            case 2:
              context.go('/clients');
            case 3:
              context.go('/invoices');
            case 4:
              context.go('/profile');
          }
        },
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Mi Perfil',
          ),
        ],
      ),
    );
  }
}
