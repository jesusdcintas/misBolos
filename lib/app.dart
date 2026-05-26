import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/security/app_lock_manager.dart';
import 'core/theme/app_theme.dart';
import 'models/app_settings.dart';
import 'providers/settings_provider.dart';
import 'providers/sync_provider.dart';
import 'core/services/google_drive_service.dart';
import 'services/sync_queue_processor.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/calendar/calendar_screen.dart';
import 'screens/calendar/gig_detail_screen.dart';
import 'screens/calendar/gig_form_screen.dart';
import 'screens/clients/client_detail_screen.dart';
import 'screens/clients/client_form_screen.dart';
import 'screens/invoices/invoice_detail_screen.dart';
import 'screens/invoices/invoice_preview_screen.dart';
import 'screens/invoices/invoice_form_screen.dart';
import 'screens/stats/stats_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/broken_attachments_screen.dart';
import 'screens/dashboard/financial_summary_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/auth/lock_screen.dart';
import 'screens/expenses/expense_form_screen.dart';
import 'screens/expenses/expense_detail_screen.dart';
import 'screens/assets/asset_form_screen.dart';
import 'screens/assets/asset_detail_screen.dart';
import 'screens/finanzas/finanzas_screen.dart';

Page<void> _slideUpPage(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondary, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final authRefresh = GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange.map((_) => null),
  );
  ref.onDispose(authRefresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: authRefresh,
    initialLocation: '/',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      final isResetPassword = state.matchedLocation == '/reset-password';
      final loggingIn =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password';

      if (session == null && !loggingIn && !isResetPassword) return '/login';
      if (isResetPassword) return null;
      if (session != null && loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/login',
        pageBuilder: (context, state) =>
            _slideUpPage(const LoginScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/register',
        pageBuilder: (context, state) =>
            _slideUpPage(const RegisterScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/forgot-password',
        pageBuilder: (context, state) =>
            _slideUpPage(const ForgotPasswordScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/reset-password',
        pageBuilder: (context, state) =>
            _slideUpPage(const ResetPasswordScreen(), state),
      ),
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
            path: '/finanzas',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const FinanzasScreen(),
              transitionDuration: const Duration(milliseconds: 200),
              transitionsBuilder: (context, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const SettingsScreen(),
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
        path: '/attachments/broken',
        pageBuilder: (context, state) =>
            _slideUpPage(const BrokenAttachmentsScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/stats',
        pageBuilder: (context, state) =>
            _slideUpPage(const StatsScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/financial',
        pageBuilder: (context, state) =>
            _slideUpPage(const FinancialSummaryScreen(), state),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/gig/new',
        pageBuilder: (context, state) =>
            _slideUpPage(const GigFormScreen(), state),
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
        pageBuilder: (context, state) =>
            _slideUpPage(const ClientFormScreen(), state),
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
          ExpenseFormScreen(expenseId: int.parse(state.pathParameters['id']!)),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/expense/:id',
        pageBuilder: (context, state) => _slideUpPage(
          ExpenseDetailScreen(
            expenseId: int.parse(state.pathParameters['id']!),
          ),
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
          AssetFormScreen(assetId: int.parse(state.pathParameters['id']!)),
          state,
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/asset/:id',
        pageBuilder: (context, state) => _slideUpPage(
          AssetDetailScreen(assetId: int.parse(state.pathParameters['id']!)),
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

class _MisBolosAppState extends ConsumerState<MisBolosApp>
    with WidgetsBindingObserver {
  bool _synced = false;
  bool _autoCloudSyncEnabled = true;
  Duration _autoCloudSyncInterval = const Duration(seconds: 45);
  Timer? _autoSyncTimer;
  Timer? _queueRetryTimer;
  Timer? _autoCloudSyncTimer;
  StreamSubscription<AuthState>? _authStateSub;
  ProviderSubscription<AsyncValue<AppSettings>>? _settingsSub;
  final AppLockManager _lockManager = AppLockManager(
    lockAfterBackground: const Duration(seconds: 4),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoSyncTimer = Timer(const Duration(seconds: 1), _autoSync);
    Timer(const Duration(milliseconds: 500), _restoreDriveSilently);
    _queueRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(
        SyncQueueProcessor.instance.processPending(reason: 'periodic_retry'),
      );
    });
    _settingsSub = ref.listenManual<AsyncValue<AppSettings>>(settingsProvider, (
      _,
      next,
    ) {
      next.whenData(_applyRuntimeSettings);
    }, fireImmediately: true);
    _authStateSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      authState,
    ) {
      if (authState.event == AuthChangeEvent.passwordRecovery) {
        ref.read(routerProvider).go('/reset-password');
      }
      _lockManager.onAuthStateChanged(authState);
      if (authState.session == null) return;
      unawaited(_syncAfterLogin());
    });
  }

  Future<void> _autoSync() async {
    if (_synced) return;
    if (!mounted) return;
    final notifier = ref.read(syncProvider.notifier);
    if (!notifier.isAuthenticated) return;
    _synced = true;
    await notifier.syncAll(reason: 'app_start');
  }

  Future<void> _syncAfterLogin() async {
    if (!mounted) return;
    final notifier = ref.read(syncProvider.notifier);
    if (!notifier.isAuthenticated) return;
    await notifier.syncAll(reason: 'auth_signed_in');
  }

  Future<void> _restoreDriveSilently() async {
    try {
      final restored = await GoogleDriveService.instance.restoreSilently();
      if (restored && mounted) {
        ref.invalidate(settingsProvider);
      }
    } catch (_) {
      // La UI conserva la carpeta local y las acciones pedirán reconectar si hace falta.
    }
  }

  Future<void> _autoCloudSyncTick() async {
    if (!_autoCloudSyncEnabled) return;
    if (!mounted) return;
    final notifier = ref.read(syncProvider.notifier);
    if (!notifier.isAuthenticated) return;
    await notifier.syncAll(reason: 'periodic_auto');
  }

  void _applyRuntimeSettings(AppSettings settings) {
    _autoCloudSyncEnabled = settings.autoCloudSyncEnabled;
    final seconds = settings.autoCloudSyncIntervalSeconds.clamp(15, 3600);
    _autoCloudSyncInterval = Duration(seconds: seconds);
    _autoCloudSyncTimer?.cancel();
    if (_autoCloudSyncEnabled) {
      _autoCloudSyncTimer = Timer.periodic(_autoCloudSyncInterval, (_) {
        unawaited(_autoCloudSyncTick());
      });
    }
    _lockManager.updateSettings(
      pinEnabled: settings.securityPinEnabled,
      pinCode: settings.securityPinCode,
      biometricEnabled: settings.securityBiometricEnabled,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lockManager.onLifecycleChanged(state);
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      SyncQueueProcessor.instance.processPending(reason: 'app_resumed'),
    );
    unawaited(_autoCloudSyncTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _queueRetryTimer?.cancel();
    _autoCloudSyncTimer?.cancel();
    _authStateSub?.cancel();
    _settingsSub?.close();
    _lockManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;

    final themeMode = switch (settings?.appThemeMode) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light,
    };

    return MaterialApp.router(
      title: 'MisBolos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      themeAnimationDuration: Duration.zero,
      routerConfig: router,
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        return AnimatedBuilder(
          animation: _lockManager,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                content,
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _lockManager.isLocked
                      ? LockScreen(
                          key: const ValueKey('app-lock-screen'),
                          manager: _lockManager,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class _ScaffoldWithNavBar extends StatefulWidget {
  final Widget child;
  const _ScaffoldWithNavBar({required this.child});

  @override
  State<_ScaffoldWithNavBar> createState() => _ScaffoldWithNavBarState();
}

class _ScaffoldWithNavBarState extends State<_ScaffoldWithNavBar> {
  static const _paths = [
    '/',
    '/calendar',
    '/finanzas',
    '/profile',
    '/settings',
  ];

  static int _indexFromLocation(String location) {
    if (location == '/') return 0;
    if (location.startsWith('/calendar')) return 1;
    if (location.startsWith('/finanzas')) return 2;
    if (location.startsWith('/profile')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _onNavTapped(int index) {
    HapticFeedback.selectionClick();
    final selectedIndex = _indexFromLocation(
      GoRouterState.of(context).uri.path,
    );
    if (index == selectedIndex) return;
    context.go(_paths[index]);
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _indexFromLocation(
      GoRouterState.of(context).uri.path,
    );

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: _onNavTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Finanzas',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
