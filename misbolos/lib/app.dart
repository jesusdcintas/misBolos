import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_colors.dart';
import 'core/security/app_lock_manager.dart';
import 'core/theme/app_theme.dart';
import 'database/database_helper.dart';
import 'models/app_settings.dart';
import 'providers/assets_provider.dart';
import 'providers/client_provider.dart';
import 'providers/expenses_provider.dart';
import 'providers/financial_summary_provider.dart';
import 'providers/gig_provider.dart';
import 'providers/invoice_provider.dart';
import 'providers/stats_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/sync_provider.dart';
import 'core/services/drive_document_sync_service.dart';
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
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/auth/lock_screen.dart';
import 'screens/expenses/expense_form_screen.dart';
import 'screens/expenses/expense_detail_screen.dart';
import 'screens/assets/asset_form_screen.dart';
import 'screens/assets/asset_detail_screen.dart';
import 'screens/finanzas/finanzas_screen.dart';
import 'screens/ai/ai_assistant_screen.dart';

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
DateTime? _lastRouterSessionSeenAt;
bool _routerExplicitSignedOut = false;

final routerProvider = Provider<GoRouter>((ref) {
  final authRefresh = GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange.map((event) {
      if (event.session != null) {
        _lastRouterSessionSeenAt = DateTime.now();
        _routerExplicitSignedOut = false;
      } else if (event.event == AuthChangeEvent.signedOut) {
        _lastRouterSessionSeenAt = null;
        _routerExplicitSignedOut = true;
      }
      return null;
    }),
  );
  ref.onDispose(authRefresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: authRefresh,
    initialLocation: '/',
    redirect: (context, state) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        _lastRouterSessionSeenAt = DateTime.now();
        _routerExplicitSignedOut = false;
      }
      final isResetPassword = state.matchedLocation == '/reset-password';
      final loggingIn =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/onboarding' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password';

      if (session == null && !loggingIn && !isResetPassword) {
        if (_routerExplicitSignedOut) return '/login';
        final lastSeen = _lastRouterSessionSeenAt;
        if (lastSeen != null &&
            DateTime.now().difference(lastSeen) < const Duration(seconds: 15)) {
          return null;
        }
        return '/login';
      }
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
        path: '/onboarding',
        pageBuilder: (context, state) =>
            _slideUpPage(const OnboardingScreen(), state),
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
        path: '/assistant',
        pageBuilder: (context, state) =>
            _slideUpPage(const AiAssistantScreen(), state),
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
    lockAfterBackground: const Duration(seconds: 5),
  );
  bool _sessionReady = false;
  bool _sessionSwitching = false;
  String _sessionMessage = 'Preparando tu espacio seguro…';
  String? _activeUserId;
  String? _lastLoginSyncUserId;
  DateTime? _lastAutoCloudSyncStartedAt;
  DateTime? _lastResumeSyncStartedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBackgroundWorkers();
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
      unawaited(_ensureSessionScope(authState.session));
      if (authState.session == null) {
        _lastLoginSyncUserId = null;
        return;
      }
      unawaited(_syncAfterLogin());
    });
    unawaited(
      _ensureSessionScope(Supabase.instance.client.auth.currentSession),
    );
  }

  void _startBackgroundWorkers() {
    _autoSyncTimer?.cancel();
    _queueRetryTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_autoSync());
    });
    _queueRetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(
        SyncQueueProcessor.instance.processPending(reason: 'periodic_retry'),
      );
    });
    Timer(const Duration(milliseconds: 500), _restoreDriveSilently);
  }

  Future<void> _ensureSessionScope(Session? session) async {
    final nextUserId = session?.user.id;
    if (_activeUserId == nextUserId && _sessionReady) return;
    setState(() {
      _sessionSwitching = true;
      _sessionReady = false;
      _sessionMessage = 'Preparando tu espacio seguro…';
    });
    _autoCloudSyncTimer?.cancel();
    _synced = false;
    _lastLoginSyncUserId = null;
    _lastAutoCloudSyncStartedAt = null;
    _lastResumeSyncStartedAt = null;
    await DatabaseHelper.instance.switchToUserDatabase(nextUserId);
    _invalidateSessionDataProviders();
    _activeUserId = nextUserId;
    if (!mounted) return;
    setState(() {
      _sessionSwitching = false;
      _sessionReady = true;
    });
  }

  void _invalidateSessionDataProviders() {
    ref.invalidate(settingsProvider);
    ref.invalidate(syncProvider);
    ref.invalidate(clientsProvider);
    ref.invalidate(gigsProvider);
    ref.invalidate(invoicesProvider);
    ref.invalidate(expensesProvider);
    ref.invalidate(assetsProvider);
    ref.invalidate(declaredQuartersProvider);
    ref.invalidate(financialSummaryProvider);
  }

  Future<void> _autoSync() async {
    if (_synced) return;
    if (!mounted) return;
    final notifier = ref.read(syncProvider.notifier);
    if (!notifier.isAuthenticated) return;
    _synced = true;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    await notifier.syncAll(reason: 'app_start');
  }

  Future<void> _syncAfterLogin() async {
    if (!mounted) return;
    if (!_sessionReady) return;
    final notifier = ref.read(syncProvider.notifier);
    if (!notifier.isAuthenticated) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _lastLoginSyncUserId == userId) return;
    if (notifier.isSyncInFlight) return;
    _lastLoginSyncUserId = userId;
    await notifier.syncAll(reason: 'auth_signed_in');
  }

  Future<void> _restoreDriveSilently() async {
    try {
      final restored = await GoogleDriveService.instance.restoreSilently();
      if (restored && mounted) {
        ref.invalidate(settingsProvider);
        unawaited(
          DriveDocumentSyncService.instance.processPendingUploads(
            reason: 'drive_restored',
          ),
        );
      }
    } catch (_) {
      // La UI conserva la carpeta local y las acciones pedirán reconectar si hace falta.
    }
  }

  Future<void> _autoCloudSyncTick() async {
    await _requestCloudSync(
      reason: 'periodic_auto',
      minInterval: _autoCloudSyncInterval,
    );
  }

  Future<void> _requestCloudSync({
    required String reason,
    required Duration minInterval,
  }) async {
    if (!_autoCloudSyncEnabled) return;
    if (!mounted) return;
    final notifier = ref.read(syncProvider.notifier);
    if (!notifier.isAuthenticated) return;
    if (notifier.isSyncInFlight) return;
    final now = DateTime.now();
    final lastStarted = _lastAutoCloudSyncStartedAt;
    if (lastStarted != null && now.difference(lastStarted) < minInterval) {
      return;
    }
    _lastAutoCloudSyncStartedAt = now;
    await notifier.syncAll(reason: reason);
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
      lockAfterBackground: Duration(
        seconds: settings.securityLockDelaySeconds.clamp(0, 3600),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lockManager.onLifecycleChanged(state);
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final lastResume = _lastResumeSyncStartedAt;
    if (lastResume != null &&
        now.difference(lastResume) < const Duration(seconds: 30)) {
      return;
    }
    _lastResumeSyncStartedAt = now;
    unawaited(
      SyncQueueProcessor.instance.processPending(reason: 'app_resumed'),
    );
    unawaited(
      DriveDocumentSyncService.instance.processPendingUploads(
        reason: 'app_resumed',
      ),
    );
    unawaited(
      _requestCloudSync(
        reason: 'app_resume',
        minInterval: const Duration(seconds: 30),
      ),
    );
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
    final settings = _sessionReady
        ? ref.watch(settingsProvider).valueOrNull
        : null;

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
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_sessionReady)
                    content
                  else
                    _SecureSessionLoading(message: _sessionMessage),
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
                  if (_sessionSwitching)
                    const ColoredBox(
                      color: Color(0xEE0B1220),
                      child: Center(
                        child: _SecureSessionLoading(
                          message: 'Preparando tu espacio seguro…',
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SecureSessionLoading extends StatelessWidget {
  final String message;
  const _SecureSessionLoading({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
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
  static const double _bolinSize = 58;
  static const double _bolinMargin = 16;
  static const double _bolinDefaultBottom = 96;

  Offset? _bolinOffset;

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
    final location = GoRouterState.of(context).uri.path;
    final selectedIndex = _indexFromLocation(location);
    final showBolin = !location.startsWith('/assistant');

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;
          final defaultOffset = Offset(
            maxWidth - _bolinSize - _bolinMargin,
            maxHeight - _bolinSize - _bolinDefaultBottom,
          );
          final effectiveOffset = _clampBolinOffset(
            _bolinOffset ?? defaultOffset,
            Size(maxWidth, maxHeight),
          );
          _bolinOffset = effectiveOffset;

          return Stack(
            children: [
              Positioned.fill(child: widget.child),
              if (showBolin)
                Positioned(
                  left: effectiveOffset.dx,
                  top: effectiveOffset.dy,
                  child: _BolinBubble(
                    size: _bolinSize,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.push('/assistant');
                    },
                    onDrag: (delta) {
                      setState(() {
                        _bolinOffset = _clampBolinOffset(
                          effectiveOffset + delta,
                          Size(maxWidth, maxHeight),
                        );
                      });
                    },
                  ),
                ),
            ],
          );
        },
      ),
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

  Offset _clampBolinOffset(Offset offset, Size size) {
    final maxX = (size.width - _bolinSize - _bolinMargin).clamp(
      _bolinMargin,
      double.infinity,
    );
    final maxY = (size.height - _bolinSize - _bolinMargin).clamp(
      _bolinMargin,
      double.infinity,
    );
    return Offset(
      offset.dx.clamp(_bolinMargin, maxX.toDouble()),
      offset.dy.clamp(_bolinMargin, maxY.toDouble()),
    );
  }
}

class _BolinBubble extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDrag;

  const _BolinBubble({
    required this.size,
    required this.onTap,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Abrir Bolín',
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: (details) => onDrag(details.delta),
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          shape: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.24),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
