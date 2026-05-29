import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/drive_document_sync_service.dart';
import '../../core/services/google_drive_service.dart';
import '../../models/app_settings.dart';
import '../../providers/assets_provider.dart';
import '../../providers/auth_controller.dart';
import '../../providers/expenses_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/google_auth_service.dart';
import '../../services/platform_auth_service.dart';
import '../../services/supabase_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _driveSearchController = TextEditingController();
  List<DriveFolderResult> _driveFolderResults = [];
  bool _driveBusy = false;
  String _driveProgressLabel = '';
  double? _driveProgressValue;
  bool _driveConnectionError = false;
  bool _calendarBusy = false;
  bool _calendarError = false;

  @override
  void initState() {
    super.initState();
    DriveDocumentSyncService.instance.progress.addListener(
      _handleDriveProgress,
    );
  }

  @override
  void dispose() {
    DriveDocumentSyncService.instance.progress.removeListener(
      _handleDriveProgress,
    );
    _driveSearchController.dispose();
    super.dispose();
  }

  void _handleDriveProgress() {
    if (!mounted) return;
    final snapshot = DriveDocumentSyncService.instance.progress.value;
    setState(() {
      _driveBusy = snapshot.active;
      _driveProgressLabel = snapshot.label;
      _driveProgressValue = snapshot.progress;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final googleAuth = ref.watch(googleAuthProvider);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.padding.bottom;
    final bottomPadding =
        (keyboardInset > 0 ? keyboardInset : bottomSafeArea) +
        kBottomNavigationBarHeight +
        24;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Perfil')),
      body: settingsAsync.when(
        data: (settings) {
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildProfileHeaderCard(settings),
                            const SizedBox(height: 12),
                            const _SyncSection(),
                            const SizedBox(height: 12),
                            Text(
                              'Conexiones',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            _buildServiceCards(settings, googleAuth, wide),
                            if (!googleAuth.isSignedIn) ...[
                              const SizedBox(height: 12),
                              _buildCloudLimitedCard(),
                            ],
                            const SizedBox(height: 12),
                            _buildAccountSecurityCard(),
                            const SizedBox(height: 12),
                            _BillingFormCard(
                              settings: settings,
                              onSaved: _saveBilling,
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildProfileHeaderCard(AppSettings settings) {
    final sync = ref.watch(syncProvider);
    final name = settings.emisorNombre.trim().isEmpty
        ? 'MisBolos'
        : settings.emisorNombre.trim();
    final mail =
        SupabaseService.instance.userEmail ?? settings.emisorEmail.trim();
    final hasCloud = SupabaseService.instance.isAuthenticated;
    final syncText = switch (sync.status) {
      SyncStatus.syncing => 'Sincronizando cambios…',
      SyncStatus.error => 'No se pudieron sincronizar algunos datos',
      SyncStatus.success => 'Todo actualizado',
      SyncStatus.idle =>
        hasCloud ? 'Sincronización activa' : 'Sin conexión en nube',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundImage: settings.logoPath.isNotEmpty
                  ? FileImage(File(settings.logoPath))
                  : null,
              child: settings.logoPath.isEmpty
                  ? const Icon(Icons.person_outline, size: 30)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (mail.isNotEmpty)
                    Text(
                      mail,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        sync.status == SyncStatus.error
                            ? Icons.error_outline
                            : sync.status == SyncStatus.syncing
                            ? Icons.sync
                            : Icons.check_circle,
                        size: 16,
                        color: sync.status == SyncStatus.error
                            ? AppColors.error
                            : sync.status == SyncStatus.syncing
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          syncText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: sync.status == SyncStatus.error
                                ? AppColors.error
                                : sync.status == SyncStatus.syncing
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (sync.lastSync != null)
                    Text(
                      'Última sincronización ${_formatDate(sync.lastSync!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCards(
    AppSettings settings,
    GoogleAuthState googleAuth,
    bool wide,
  ) {
    final driveState = _driveState(settings, googleAuth);
    final calendarState = _calendarState(googleAuth);
    final cards = [
      _serviceStatusCard(
        title: 'Cuenta Google',
        icon: Icons.account_circle_outlined,
        status: googleAuth.isSignedIn ? 'Conectada' : 'No conectada',
        subtitle:
            googleAuth.email ?? 'Inicia sesión para activar servicios cloud.',
        tone: googleAuth.isSignedIn ? _ServiceTone.ready : _ServiceTone.neutral,
        onTap: () => googleAuth.isSignedIn
            ? _showGoogleAccountSheet(googleAuth)
            : ref.read(googleAuthProvider.notifier).signIn(),
      ),
      FutureBuilder<DriveConnectionCheck>(
        future: GoogleDriveService.instance.checkDriveConnectionStatus(),
        builder: (context, snapshot) {
          final check = snapshot.data;
          final effectiveState = check == null
              ? driveState
              : _driveStateFromConnection(check.status);
          return _serviceStatusCard(
            title: 'Google Drive',
            icon: Icons.add_to_drive_outlined,
            status: check == null
                ? _driveStatusText(driveState)
                : _driveStatusText(effectiveState),
            subtitle: check?.message ?? _driveSubtitleText(driveState, settings),
            tone: _driveTone(effectiveState),
            onTap: () => _handleDriveCardTap(effectiveState, settings),
          );
        },
      ),
      _serviceStatusCard(
        title: 'Google Calendar',
        icon: Icons.calendar_month_outlined,
        status: _calendarStatusText(calendarState),
        subtitle: _calendarSubtitleText(calendarState),
        tone: _calendarTone(calendarState),
        onTap: () => _handleCalendarCardTap(calendarState, googleAuth),
      ),
    ];

    if (wide) {
      return Row(
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 8),
          Expanded(child: cards[1]),
          const SizedBox(width: 8),
          Expanded(child: cards[2]),
        ],
      );
    }
    return Column(
      children: [
        cards[0],
        const SizedBox(height: 8),
        cards[1],
        const SizedBox(height: 8),
        cards[2],
      ],
    );
  }

  Widget _serviceStatusCard({
    required String title,
    required IconData icon,
    required String status,
    required String subtitle,
    required _ServiceTone tone,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final toneColor = switch (tone) {
      _ServiceTone.ready => AppColors.success,
      _ServiceTone.warning => AppColors.warning,
      _ServiceTone.error => AppColors.error,
      _ServiceTone.syncing => cs.primary,
      _ServiceTone.neutral => AppColors.textMuted,
    };
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 260),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - v)),
          child: child,
        ),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: toneColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        status,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: toneColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveBilling(_BillingFormData data) async {
    final current = await ref.read(settingsProvider.future);
    final settings = current.copyWith(
      logoPath: data.logoPath,
      emisorNombre: data.nombre,
      emisorNIF: data.nif,
      emisorDireccion: data.direccion,
      emisorCiudad: data.ciudad,
      emisorEmail: data.email,
      emisorTelefono: data.telefono,
      iban: data.iban,
    );

    await ref.read(settingsProvider.notifier).save(settings);
    if (SupabaseService.instance.isAuthenticated) {
      try {
        await SupabaseService.instance.uploadSettings(settings);
        await ref
            .read(settingsProvider.notifier)
            .save(
              settings.copyWith(
                cloudSettingsSignature: SupabaseService.instance
                    .settingsSyncSignature(settings),
              ),
            );
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil guardado')));
    }
  }

  Widget _buildCloudLimitedCard() {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 320),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: Card(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: 0.38),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Funciones cloud limitadas',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Conecta Google para activar sincronización automática, Google Drive y calendario.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () =>
                          ref.read(googleAuthProvider.notifier).signIn(),
                      child: const Text('Conectar Google'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _DriveServiceState _driveState(AppSettings settings, GoogleAuthState auth) {
    final hasFolderId = settings.driveRootFolderId?.trim().isNotEmpty ?? false;
    final hasFolderName =
        settings.driveRootFolderName?.trim().isNotEmpty ?? false;
    final folderConfigured = hasFolderId && hasFolderName;
    final googleSignedIn = auth.isSignedIn;
    final driveAuthorized = settings.driveConnected;
    if (_driveBusy) return _DriveServiceState.syncing;
    if (_driveConnectionError) return _DriveServiceState.error;
    if (!googleSignedIn || !driveAuthorized) {
      return _DriveServiceState.disconnected;
    }
    if (!folderConfigured) return _DriveServiceState.connectedUnconfigured;
    return _DriveServiceState.ready;
  }

  _DriveServiceState _driveStateFromConnection(DriveConnectionStatus status) {
    if (_driveBusy) return _DriveServiceState.syncing;
    if (_driveConnectionError) return _DriveServiceState.error;
    switch (status) {
      case DriveConnectionStatus.connected:
        return _DriveServiceState.ready;
      case DriveConnectionStatus.missingFolder:
      case DriveConnectionStatus.googleConnectedNoDrive:
      case DriveConnectionStatus.permissionMissing:
      case DriveConnectionStatus.folderNotAccessible:
        return _DriveServiceState.connectedUnconfigured;
      case DriveConnectionStatus.disconnected:
        return _DriveServiceState.disconnected;
      case DriveConnectionStatus.error:
        return _DriveServiceState.error;
    }
  }

  _CalendarServiceState _calendarState(GoogleAuthState auth) {
    if (_calendarBusy) return _CalendarServiceState.syncing;
    if (_calendarError) return _CalendarServiceState.error;
    if (!auth.isSignedIn) return _CalendarServiceState.disconnected;
    if (!auth.calendarConnected) {
      return _CalendarServiceState.connectedUnconfigured;
    }
    return _CalendarServiceState.ready;
  }

  String _driveStatusText(_DriveServiceState state) => switch (state) {
    _DriveServiceState.disconnected => 'No conectado',
    _DriveServiceState.connectedUnconfigured => 'Configuración pendiente',
    _DriveServiceState.ready => 'Listo',
    _DriveServiceState.syncing => 'Sincronizando…',
    _DriveServiceState.error => 'Error de conexión',
  };

  String _driveSubtitleText(_DriveServiceState state, AppSettings settings) {
    switch (state) {
      case _DriveServiceState.disconnected:
        return 'Conecta Drive para sincronizar documentos.';
      case _DriveServiceState.connectedUnconfigured:
        return 'Selecciona una carpeta para guardar documentos y sincronizar archivos.';
      case _DriveServiceState.ready:
        return 'Sincronización de documentos activa.';
      case _DriveServiceState.syncing:
        return _driveProgressLabel.isNotEmpty
            ? _driveProgressLabel
            : 'Aplicando cambios en Google Drive.';
      case _DriveServiceState.error:
        return 'Se requiere volver a conectar Google Drive.';
    }
  }

  _ServiceTone _driveTone(_DriveServiceState state) => switch (state) {
    _DriveServiceState.disconnected => _ServiceTone.neutral,
    _DriveServiceState.connectedUnconfigured => _ServiceTone.warning,
    _DriveServiceState.ready => _ServiceTone.ready,
    _DriveServiceState.syncing => _ServiceTone.syncing,
    _DriveServiceState.error => _ServiceTone.error,
  };

  String _calendarStatusText(_CalendarServiceState state) => switch (state) {
    _CalendarServiceState.disconnected => 'No conectado',
    _CalendarServiceState.connectedUnconfigured => 'Configuración pendiente',
    _CalendarServiceState.ready => 'Listo',
    _CalendarServiceState.syncing => 'Sincronizando…',
    _CalendarServiceState.error => 'Error de conexión',
  };

  String _calendarSubtitleText(_CalendarServiceState state) {
    switch (state) {
      case _CalendarServiceState.disconnected:
        return 'Conecta Calendar para sincronizar tu agenda de bolos.';
      case _CalendarServiceState.connectedUnconfigured:
        return 'Completa la conexión para activar la sincronización.';
      case _CalendarServiceState.ready:
        return 'Sincronización de agenda activa.';
      case _CalendarServiceState.syncing:
        return 'Aplicando cambios en Google Calendar.';
      case _CalendarServiceState.error:
        return 'Se requiere volver a conectar Google Calendar.';
    }
  }

  _ServiceTone _calendarTone(_CalendarServiceState state) => switch (state) {
    _CalendarServiceState.disconnected => _ServiceTone.neutral,
    _CalendarServiceState.connectedUnconfigured => _ServiceTone.warning,
    _CalendarServiceState.ready => _ServiceTone.ready,
    _CalendarServiceState.syncing => _ServiceTone.syncing,
    _CalendarServiceState.error => _ServiceTone.error,
  };

  Future<void> _handleDriveCardTap(
    _DriveServiceState state,
    AppSettings settings,
  ) async {
    switch (state) {
      case _DriveServiceState.disconnected:
        await _connectDrive();
        break;
      case _DriveServiceState.connectedUnconfigured:
        _showDrivePanel();
        break;
      case _DriveServiceState.error:
        await _connectDrive();
        break;
      case _DriveServiceState.ready:
      case _DriveServiceState.syncing:
        _showDrivePanel();
        break;
    }
  }

  Future<void> _handleCalendarCardTap(
    _CalendarServiceState state,
    GoogleAuthState auth,
  ) async {
    switch (state) {
      case _CalendarServiceState.disconnected:
        await _runCalendarAction(() async {
          final ok = await ref.read(googleAuthProvider.notifier).signIn();
          if (!ok) {
            throw Exception('No se pudo iniciar sesión con Google.');
          }
        }, successMessage: 'Cuenta Google conectada');
        break;
      case _CalendarServiceState.connectedUnconfigured:
      case _CalendarServiceState.error:
        await _runCalendarAction(() async {
          final ok = await ref
              .read(googleAuthProvider.notifier)
              .connectCalendarOnly();
          if (!ok) {
            throw Exception('No se pudo completar la conexión de Calendar.');
          }
        }, successMessage: 'Google Calendar conectado');
        break;
      case _CalendarServiceState.ready:
      case _CalendarServiceState.syncing:
        _showCalendarPanel(auth);
        break;
    }
  }

  void _showGoogleAccountSheet(GoogleAuthState auth) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cuenta Google',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(auth.email ?? 'Cuenta conectada'),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(googleAuthProvider.notifier).signOut();
                },
                child: const Text('Desconectar Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDrivePanel() {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.88,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                _buildGoogleDriveSection(settings),
                const SizedBox(height: 10),
                _buildDriveHelpSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCalendarPanel(GoogleAuthState auth) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: _buildCalendarSection(auth),
        ),
      ),
    );
  }

  Widget _buildAccountSecurityCard() {
    final user = SupabaseService.instance.currentUser;
    final identities = user?.identities ?? const <UserIdentity>[];
    final hasGoogle = identities.any((i) => i.provider == 'google');
    final hasEmailPassword = identities.any((i) => i.provider == 'email');
    final method = hasGoogle && hasEmailPassword
        ? 'Google + contraseña'
        : hasGoogle
        ? 'Google'
        : 'Email y contraseña';
    final passwordConfigured = hasEmailPassword;
    final email = user?.email ?? 'Sin email';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cuenta',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text('Email: $email'),
            const SizedBox(height: 4),
            Text('Método de acceso: $method'),
            const SizedBox(height: 4),
            Text(
              'Contraseña: ${passwordConfigured ? 'Configurada' : 'No configurada'}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _sendPasswordSetupOrReset,
                  child: Text(
                    passwordConfigured
                        ? 'Cambiar contraseña'
                        : 'Crear contraseña',
                  ),
                ),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  onPressed: _confirmDeleteAccount,
                  child: const Text('Eliminar cuenta'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPasswordSetupOrReset() async {
    try {
      await SupabaseService.instance.requestCreateOrResetPassword();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Te hemos enviado un enlace para crear o cambiar tu contraseña.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error enviando email: $e')));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se eliminarán tus datos sincronizados, facturas, clientes, gastos, inversiones y configuración de esta cuenta. Esta acción no se puede deshacer.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Escribe ELIMINAR'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim() == 'ELIMINAR'),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true) return;

    try {
      await SupabaseService.instance.deleteCurrentAccount();
      await ref.read(authControllerProvider.notifier).signOut();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo eliminar la cuenta. Verifica la Edge Function delete-user-account. Error: $e',
          ),
        ),
      );
    }
  }

  Widget _buildDriveHelpSection() {
    Widget item(String title, String desc) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            children: [
              TextSpan(
                text: '$title: ',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: desc),
            ],
          ),
        ),
      );
    }

    return Card(
      color: AppColors.primaryLight.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.info_outline, size: 16),
                SizedBox(width: 6),
                Text(
                  'Ayuda rápida (Drive)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            item(
              'Reintentar válidos',
              'vuelve a intentar subir archivos que fallaron por red o permisos.',
            ),
            item(
              'Limpiar inválidos',
              'elimina pendientes imposibles de subir (archivo ya no existe o ruta rota).',
            ),
            item(
              'Reparar facturas Drive',
              'regenera PDFs de facturas para poder subirlos de nuevo.',
            ),
            item(
              'Adjuntos rotos',
              'lista de documentos que faltan o ya no están disponibles en este dispositivo.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarSection(GoogleAuthState auth) {
    final connected = auth.calendarConnected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google Calendar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              connected
                  ? 'Calendario conectado'
                  : 'Sincronización de calendario no conectada',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!connected)
                  ElevatedButton.icon(
                    onPressed: () => ref
                        .read(googleAuthProvider.notifier)
                        .connectCalendarOnly(),
                    icon: const Icon(Icons.calendar_month),
                    label: const Text('Conectar Calendar'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(googleAuthProvider.notifier).signOut(),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Desconectar Calendar'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleDriveSection(AppSettings settings) {
    final connected = settings.driveConnected;
    final hasFolder =
        (settings.driveRootFolderId?.trim().isNotEmpty ?? false) &&
        (settings.driveRootFolderName?.trim().isNotEmpty ?? false);
    final driveReady = connected && hasFolder;
    final rootName = settings.driveRootFolderName;
    final rootId = settings.driveRootFolderId;
    final accountLabel = _driveAccountLabel(settings);
    final hasDriveAccount =
        settings.driveAccountEmail?.trim().isNotEmpty == true ||
        settings.driveAccountName?.trim().isNotEmpty == true;
    final statusLabel = driveReady
        ? 'Drive listo'
        : hasFolder || hasDriveAccount
        ? 'Requiere configuración'
        : 'Drive no conectado';
    final statusBg = !driveReady && !hasFolder && !hasDriveAccount
        ? AppColors.errorBg
        : driveReady
        ? AppColors.successBg
        : AppColors.warningBg;
    final statusFg = !driveReady && !hasFolder && !hasDriveAccount
        ? AppColors.error
        : driveReady
        ? AppColors.success
        : AppColors.warning;
    final statusIcon = !driveReady && !hasFolder && !hasDriveAccount
        ? Icons.error_outline
        : driveReady
        ? Icons.check_circle
        : Icons.warning_amber_rounded;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connected ? Icons.add_to_drive : Icons.add_to_drive_outlined,
                  color: connected ? AppColors.success : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Google Drive',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        'Estado de cuenta y carpeta de trabajo',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_driveBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (_driveBusy) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _driveProgressValue,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 6),
              Text(
                (_driveProgressLabel.isEmpty
                        ? 'Procesando en Google Drive...'
                        : _driveProgressLabel) +
                    (_driveProgressValue != null
                        ? ' · ${(_driveProgressValue! * 100).toStringAsFixed(0)}%'
                        : ''),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, size: 18, color: statusFg),
                  const SizedBox(width: 8),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: statusFg,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<DriveConnectionCheck>(
              future: GoogleDriveService.instance.checkDriveConnectionStatus(),
              builder: (context, snapshot) {
                final check = snapshot.data;
                if (check == null) {
                  return const Text(
                    'Diagnosticando conexión de Drive...',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  );
                }
                return Text(
                  check.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: check.isConnected
                        ? AppColors.success
                        : AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        connected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: connected
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        connected ? 'Cuenta conectada' : 'Cuenta no conectada',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: connected
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    connected || hasDriveAccount
                        ? accountLabel
                        : 'Conecta Google Drive para activar la sincronización documental.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (settings.lastDriveSyncAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Última subida: ${_formatDate(settings.lastDriveSyncAt!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!connected)
                        ElevatedButton.icon(
                          onPressed: _driveBusy ? null : _connectDrive,
                          icon: const Icon(Icons.login),
                          label: const Text('Conectar Google Drive'),
                        )
                      else ...[
                        OutlinedButton.icon(
                          onPressed: _driveBusy ? null : _connectDrive,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reconectar cuenta'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _driveBusy ? null : _disconnectDrive,
                          icon: const Icon(Icons.logout),
                          label: const Text('Desconectar Drive'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasFolder
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        size: 18,
                        color: hasFolder
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasFolder
                            ? 'Carpeta seleccionada'
                            : 'Carpeta no seleccionada',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: hasFolder
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (hasFolder) ...[
                    Text(
                      rootName!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rootId?.isNotEmpty == true)
                      Text(
                        rootId!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ] else
                    const Text(
                      'Selecciona dónde guardar facturas, gastos e inversiones.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!hasFolder) ...[
                        ElevatedButton.icon(
                          onPressed: _driveBusy
                              ? null
                              : () => _runDriveAction(
                                  () async {
                                    final setup = await GoogleDriveService
                                        .instance
                                        .setupWorkspace();
                                    if (!setup.ready) {
                                      throw Exception(
                                        setup.message ??
                                            'No se pudo crear carpeta automática.',
                                      );
                                    }
                                    ref.invalidate(settingsProvider);
                                  },
                                  progressLabel: 'Creando carpeta MisBolos...',
                                  successMessage: 'Carpeta MisBolos creada',
                                  errorPrefix:
                                      'No se pudo crear carpeta MisBolos',
                                ),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('Crear carpeta MisBolos'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _driveBusy ? null : _searchDriveFolders,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Elegir carpeta existente'),
                        ),
                      ] else
                        ElevatedButton.icon(
                          onPressed: _driveBusy ? null : _searchDriveFolders,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Cambiar carpeta'),
                        ),
                      OutlinedButton.icon(
                        onPressed: (!_driveBusy && hasFolder)
                            ? () => _openDriveFolder(rootId!)
                            : null,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Ver carpeta'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _driveSearchController,
              decoration: InputDecoration(
                labelText: 'Buscar carpeta',
                hintText: 'MisBolos Test',
                suffixIcon: IconButton(
                  tooltip: 'Buscar',
                  onPressed: _driveBusy ? null : _searchDriveFolders,
                  icon: const Icon(Icons.search),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _searchDriveFolders(),
            ),
            if (_driveFolderResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._driveFolderResults.map(
                (folder) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  subtitle: Text(
                    folder.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: _driveBusy
                        ? null
                        : () => _selectDriveFolder(folder),
                    child: const Text('Seleccionar'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: (!_driveBusy && driveReady)
                      ? _createDriveStructure
                      : null,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Crear estructura'),
                ),
                OutlinedButton.icon(
                  onPressed: (!_driveBusy && driveReady)
                      ? _uploadDocumentsToDrive
                      : null,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Subir documentos a Drive'),
                ),
                OutlinedButton.icon(
                  onPressed: (!_driveBusy && driveReady)
                      ? _syncDriveDocuments
                      : null,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Sincronizar documentos'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Configuración avanzada'),
              subtitle: const Text('Reparación, reintentos y diagnóstico'),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: (!_driveBusy && driveReady)
                          ? _retryPendingDriveSync
                          : null,
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('Reintentar subidas pendientes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _driveBusy ? null : _diagnoseDriveConnection,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Diagnosticar conexión'),
                    ),
                    OutlinedButton.icon(
                      onPressed: (!_driveBusy && driveReady)
                          ? _clearInvalidDrivePending
                          : null,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Limpiar inválidos'),
                    ),
                    OutlinedButton.icon(
                      onPressed: (!_driveBusy && driveReady)
                          ? _repairLegacyAttachments
                          : null,
                      icon: const Icon(Icons.build_circle_outlined),
                      label: const Text('Reparar adjuntos'),
                    ),
                    OutlinedButton.icon(
                      onPressed: (!_driveBusy && driveReady)
                          ? _repairPendingInvoiceDrivePdfs
                          : null,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Reparar facturas Drive'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/attachments/broken'),
                      icon: const Icon(Icons.broken_image_outlined),
                      label: const Text('Adjuntos rotos'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FutureBuilder<DriveQueueSummary>(
                  future: DriveDocumentSyncService.instance.getQueueSummary(),
                  builder: (context, snapshot) {
                    final s = snapshot.data ?? const DriveQueueSummary();
                    return Text(
                      s.totalPending > 0
                          ? 'Pendientes Drive válidos: ${s.totalPending} · facturas ${s.invoicePending} · gastos ${s.expensePending} · inversiones ${s.assetPending} · retryables ${s.retryable}'
                          : 'Sin pendientes en cola de Drive',
                      style: TextStyle(
                        fontSize: 12,
                        color: s.totalPending > 0
                            ? AppColors.warning
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
                FutureBuilder<DriveQueueSummary>(
                  future: DriveDocumentSyncService.instance.getQueueSummary(),
                  builder: (context, snapshot) {
                    final s = snapshot.data ?? const DriveQueueSummary();
                    if (s.invalidMissingFile == 0 && s.invalidDevicePath == 0) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      'Adjuntos rotos: ${s.invalidMissingFile + s.invalidDevicePath} · no encontrado ${s.invalidMissingFile} · otro dispositivo ${s.invalidDevicePath}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'La app solo creará o reutilizará carpetas dentro de la carpeta seleccionada. No borra, mueve ni renombra archivos.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  String _driveAccountLabel(AppSettings settings) {
    final email = settings.driveAccountEmail;
    final name = settings.driveAccountName;
    if (name?.isNotEmpty == true && email?.isNotEmpty == true) {
      return '$name · $email';
    }
    if (email?.isNotEmpty == true) return email!;
    if (name?.isNotEmpty == true) return name!;
    return 'Sin cuenta conectada';
  }

  Future<void> _connectDrive() async {
    await _runDriveAction(
      () async {
        await GoogleDriveService.instance.signIn();
        final setup = await GoogleDriveService.instance.setupWorkspace();
        if (!setup.ready && mounted) {
          _showDriveMessage(
            'Selecciona una carpeta manualmente para completar la configuración de Drive.',
          );
        }
        await DriveDocumentSyncService.instance.processPendingUploads(
          reason: 'drive_connected',
        );
        ref.invalidate(settingsProvider);
      },
      progressLabel: 'Conectando Google Drive y preparando espacio...',
      successMessage: 'Drive listo',
      errorPrefix: 'No se pudo conectar con Google Drive',
    );
  }

  Future<void> _disconnectDrive() async {
    await _runDriveAction(
      () async {
        await GoogleDriveService.instance.signOut();
        _driveFolderResults = [];
        ref.invalidate(settingsProvider);
      },
      progressLabel: 'Desconectando Google Drive...',
      successMessage: 'Google Drive desconectado',
      errorPrefix: 'No se pudo desconectar Google Drive',
    );
  }

  Future<void> _searchDriveFolders() async {
    await _runDriveAction(
      () async {
        final results = await GoogleDriveService.instance.searchFoldersByName(
          _driveSearchController.text,
        );
        setState(() => _driveFolderResults = results);
        if (results.isEmpty) {
          throw Exception('No se encontraron carpetas con ese nombre.');
        }
      },
      progressLabel: 'Buscando carpetas en Drive...',
      successMessage: 'Carpetas encontradas',
      errorPrefix: 'No se pudo buscar la carpeta',
    );
  }

  Future<void> _selectDriveFolder(DriveFolderResult folder) async {
    await _runDriveAction(
      () async {
        await GoogleDriveService.instance.selectRootFolder(folder);
        await DriveDocumentSyncService.instance.processPendingUploads(
          reason: 'drive_folder_selected',
        );
        ref.invalidate(settingsProvider);
      },
      progressLabel: 'Guardando carpeta seleccionada...',
      successMessage: 'Carpeta de trabajo seleccionada',
      errorPrefix: 'No se pudo seleccionar la carpeta',
    );
  }

  Future<void> _createDriveStructure() async {
    await _runDriveAction(
      () async {
        final result = await DriveDocumentSyncService.instance
            .createStructureForExistingDocuments(
              reason: 'manual_create_structure',
            );
        debugPrint(
          '[DRIVE][STRUCTURE] requested_from_profile years=${result.years.join(', ')}',
        );
      },
      progressLabel: 'Creando estructura anual en Drive...',
      successMessage:
          'Estructura creada correctamente. Si ya existía, se ha reutilizado.',
      errorPrefix: 'No se pudo crear la estructura de Drive',
    );
  }

  Future<void> _openDriveFolder(String folderId) async {
    await _runDriveAction(
      () async {
        await GoogleDriveService.instance.openFolder(folderId);
      },
      progressLabel: 'Abriendo carpeta en Google Drive...',
      errorPrefix: 'No se pudo abrir la carpeta de Drive',
    );
  }

  Future<void> _syncDriveDocuments() async {
    final settings = await ref.read(settingsProvider.future);
    final isReady =
        settings.driveConnected &&
        (settings.driveRootFolderId?.trim().isNotEmpty ?? false);
    if (!isReady) {
      _showDriveMessage(
        'Conecta Google Drive y selecciona una carpeta antes de sincronizar.',
      );
      return;
    }
    await _runDriveAction(
      () async {
        final result = await DriveDocumentSyncService.instance
            .syncExistingDocuments(reason: 'drive_sync');
        ref.invalidate(settingsProvider);
        ref.invalidate(invoicesProvider);
        ref.invalidate(expensesProvider);
        ref.invalidate(assetsProvider);
        _showDriveMessage(
          'Documentos sincronizados: ${result.uploaded} subidos/actualizados, '
          '${result.skipped} omitidos, ${result.failed} pendientes.',
        );
      },
      progressLabel: 'Sincronizando documentos con Drive...',
      errorPrefix: 'No se pudo sincronizar documentos',
    );
  }

  Future<void> _uploadDocumentsToDrive() async {
    final settings = await ref.read(settingsProvider.future);
    final isReady =
        settings.driveConnected &&
        (settings.driveRootFolderId?.trim().isNotEmpty ?? false);
    if (!isReady) {
      _showDriveMessage(
        'Conecta Google Drive y selecciona una carpeta antes de subir documentos.',
      );
      return;
    }
    await _runDriveAction(
      () async {
        final result = await DriveDocumentSyncService.instance
            .uploadAllDocumentsToDrive(reason: 'drive_full_upload');
        ref.invalidate(settingsProvider);
        ref.invalidate(invoicesProvider);
        ref.invalidate(expensesProvider);
        ref.invalidate(assetsProvider);
        _showDriveMessage(
          'Subidos ${result.uploaded} · ya existían ${result.alreadyExists} · '
          'faltan localmente ${result.missingLocal} · errores ${result.errors}',
        );
      },
      progressLabel: 'Subiendo documentos a Drive...',
      errorPrefix: 'No se pudieron subir documentos a Drive',
    );
  }

  Future<void> _retryPendingDriveSync() async {
    await _runDriveAction(
      () async {
        final result = await DriveDocumentSyncService.instance
            .retryPendingDriveSync();
        ref.invalidate(settingsProvider);
        ref.invalidate(invoicesProvider);
        ref.invalidate(expensesProvider);
        ref.invalidate(assetsProvider);
        if (!mounted) return;
        final extra = result.recentErrors.isEmpty
            ? ''
            : '\nErrores: ${result.recentErrors.join(' | ')}';
        _showDriveMessage(
          'Reintento Drive: ${result.succeeded} ok, ${result.failed} fallos, '
          '${result.skippedByMaxAttempts} al límite.$extra',
        );
      },
      progressLabel: 'Reintentando pendientes válidos de Drive...',
      errorPrefix: 'No se pudieron reintentar pendientes de Drive',
    );
  }

  Future<void> _diagnoseDriveConnection() async {
    await _runDriveAction(
      () async {
        final status = await GoogleDriveService.instance
            .checkDriveConnectionStatus();
        ref.invalidate(settingsProvider);
        _showDriveMessage(status.message);
      },
      progressLabel: 'Diagnosticando Google Drive...',
      errorPrefix: 'No se pudo diagnosticar Google Drive',
    );
  }

  Future<void> _clearInvalidDrivePending() async {
    await _runDriveAction(
      () async {
        final removed = await DriveDocumentSyncService.instance
            .clearInvalidQueueEntries();
        _showDriveMessage('Pendientes inválidos eliminados: $removed');
      },
      progressLabel: 'Limpiando pendientes inválidos...',
      errorPrefix: 'No se pudieron limpiar pendientes inválidos',
    );
  }

  Future<void> _repairLegacyAttachments() async {
    await _runDriveAction(
      () async {
        final result = await DriveDocumentSyncService.instance
            .repairLegacyAttachmentPaths();
        _showDriveMessage(
          '${result.missing + result.unavailable} adjuntos no disponibles. Revisa adjuntos rotos.',
        );
      },
      progressLabel: 'Reparando adjuntos heredados...',
      errorPrefix: 'No se pudieron reparar adjuntos',
    );
  }

  Future<void> _repairPendingInvoiceDrivePdfs() async {
    await _runDriveAction(
      () async {
        final repaired = await DriveDocumentSyncService.instance
            .repairPendingInvoicePdfs();
        _showDriveMessage('Facturas reparadas para Drive: $repaired');
      },
      progressLabel: 'Regenerando PDFs de facturas pendientes...',
      errorPrefix: 'No se pudieron reparar facturas pendientes',
    );
  }

  Future<void> _runDriveAction(
    Future<void> Function() action, {
    String? progressLabel,
    String? successMessage,
    required String errorPrefix,
  }) async {
    if (_driveBusy) return;
    setState(() {
      _driveBusy = true;
      _driveProgressLabel = progressLabel ?? 'Procesando en Google Drive...';
    });
    try {
      await action();
      _driveConnectionError = false;
      if (mounted && successMessage != null) {
        _showDriveMessage(successMessage);
      }
    } catch (e) {
      _driveConnectionError = true;
      if (mounted) {
        _showDriveMessage('$errorPrefix: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _driveBusy = false;
          _driveProgressLabel = '';
        });
      }
    }
  }

  Future<void> _runCalendarAction(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_calendarBusy) return;
    setState(() => _calendarBusy = true);
    try {
      await action();
      _calendarError = false;
      if (mounted && successMessage != null) {
        _showDriveMessage(successMessage);
      }
    } catch (e) {
      _calendarError = true;
      if (mounted) {
        _showDriveMessage('No se pudo conectar Google Calendar: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _calendarBusy = false);
      }
    }
  }

  void _showDriveMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }
}

enum _DriveServiceState {
  disconnected,
  connectedUnconfigured,
  ready,
  syncing,
  error,
}

enum _CalendarServiceState {
  disconnected,
  connectedUnconfigured,
  ready,
  syncing,
  error,
}

enum _ServiceTone { neutral, warning, ready, syncing, error }

// ── Google Account Section ──

// ignore: unused_element
class _GoogleSection extends ConsumerWidget {
  final GoogleAuthState auth;
  const _GoogleSection({required this.auth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!auth.isSignedIn) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(
                Icons.account_circle,
                size: 64,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              const Text(
                'Conexiones de Google',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Conecta Calendar para sincronizar bolos y agenda',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Iniciar sesión con Google'),
                  onPressed: () =>
                      ref.read(googleAuthProvider.notifier).signIn(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                auth.photoUrl != null
                    ? CircleAvatar(
                        radius: 28,
                        backgroundImage: NetworkImage(auth.photoUrl!),
                      )
                    : const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.person, size: 28),
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.displayName ?? 'Usuario',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (auth.email != null)
                        Text(
                          auth.email!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Google Calendar ──
          if (auth.calendarConnected)
            const ListTile(
              leading: Icon(Icons.calendar_month, color: AppColors.primary),
              title: Text('Google Calendar'),
              subtitle: Text('Bolos sincronizados'),
              trailing: Icon(
                Icons.check_circle,
                color: AppColors.accentGreen,
                size: 20,
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.calendar_month, color: Colors.orange),
              title: const Text('Google Calendar'),
              subtitle: const Text('Sin sincronizar · Toca para conectar'),
              trailing: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 20,
              ),
              onTap: () =>
                  ref.read(googleAuthProvider.notifier).connectCalendarOnly(),
            ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline, color: AppColors.textSecondary),
            title: Text('Sesión principal'),
            subtitle: Text(
              'Para salir de MisBolos usa "Cerrar sesión" en Sincronización en la nube.',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Logo Selector ──

class _BillingFormData {
  final String logoPath;
  final String nombre;
  final String nif;
  final String email;
  final String telefono;
  final String direccion;
  final String ciudad;
  final String iban;

  const _BillingFormData({
    required this.logoPath,
    required this.nombre,
    required this.nif,
    required this.email,
    required this.telefono,
    required this.direccion,
    required this.ciudad,
    required this.iban,
  });
}

class _BillingFormCard extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(_BillingFormData data) onSaved;

  const _BillingFormCard({required this.settings, required this.onSaved});

  @override
  State<_BillingFormCard> createState() => _BillingFormCardState();
}

class _BillingFormCardState extends State<_BillingFormCard> {
  late final TextEditingController _nombreController;
  late final TextEditingController _nifController;
  late final TextEditingController _emailController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _direccionController;
  late final TextEditingController _ciudadController;
  late final TextEditingController _ibanController;

  late final FocusNode _nombreFocus;
  late final FocusNode _nifFocus;
  late final FocusNode _emailFocus;
  late final FocusNode _telefonoFocus;
  late final FocusNode _direccionFocus;
  late final FocusNode _ciudadFocus;
  late final FocusNode _ibanFocus;

  late String _logoPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController(
      text: widget.settings.emisorNombre,
    );
    _nifController = TextEditingController(text: widget.settings.emisorNIF);
    _emailController = TextEditingController(text: widget.settings.emisorEmail);
    _telefonoController = TextEditingController(
      text: widget.settings.emisorTelefono,
    );
    _direccionController = TextEditingController(
      text: widget.settings.emisorDireccion,
    );
    _ciudadController = TextEditingController(
      text: widget.settings.emisorCiudad,
    );
    _ibanController = TextEditingController(text: widget.settings.iban);

    _nombreFocus = FocusNode();
    _nifFocus = FocusNode();
    _emailFocus = FocusNode();
    _telefonoFocus = FocusNode();
    _direccionFocus = FocusNode();
    _ciudadFocus = FocusNode();
    _ibanFocus = FocusNode();

    _logoPath = widget.settings.logoPath;
  }

  @override
  void didUpdateWidget(covariant _BillingFormCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncIfExternalChanged(widget.settings);
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _nifController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _ciudadController.dispose();
    _ibanController.dispose();

    _nombreFocus.dispose();
    _nifFocus.dispose();
    _emailFocus.dispose();
    _telefonoFocus.dispose();
    _direccionFocus.dispose();
    _ciudadFocus.dispose();
    _ibanFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Datos de facturación',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _LogoSelector(
              logoPath: _logoPath,
              onPick: _pickLogo,
              onRemove: () => setState(() => _logoPath = ''),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final mobile = constraints.maxWidth < 760;
                if (mobile) {
                  return Column(
                    children: [
                      _fieldBox(
                        width: double.infinity,
                        child: FiscalTextField(
                          key: const ValueKey('fiscal_name'),
                          controller: _nombreController,
                          focusNode: _nombreFocus,
                          labelText: AppStrings.nombre,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      _fieldBox(
                        width: double.infinity,
                        child: FiscalTextField(
                          key: const ValueKey('fiscal_nif'),
                          controller: _nifController,
                          focusNode: _nifFocus,
                          labelText: 'NIF/CIF',
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      _fieldBox(
                        width: double.infinity,
                        child: FiscalTextField(
                          key: const ValueKey('fiscal_email'),
                          controller: _emailController,
                          focusNode: _emailFocus,
                          labelText: AppStrings.email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      _fieldBox(
                        width: double.infinity,
                        child: FiscalTextField(
                          key: const ValueKey('fiscal_phone'),
                          controller: _telefonoController,
                          focusNode: _telefonoFocus,
                          labelText: AppStrings.telefono,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      _fieldBox(
                        width: double.infinity,
                        child: FiscalTextField(
                          key: const ValueKey('fiscal_address'),
                          controller: _direccionController,
                          focusNode: _direccionFocus,
                          labelText: AppStrings.direccion,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      _fieldBox(
                        width: double.infinity,
                        child: FiscalTextField(
                          key: const ValueKey('fiscal_city'),
                          controller: _ciudadController,
                          focusNode: _ciudadFocus,
                          labelText: AppStrings.ciudad,
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      _fieldBox(
                        width: double.infinity,
                        child: FiscalTextField(
                          key: const ValueKey('fiscal_iban'),
                          controller: _ibanController,
                          focusNode: _ibanFocus,
                          labelText: 'IBAN',
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FiscalTextField(
                            key: const ValueKey('fiscal_name'),
                            controller: _nombreController,
                            focusNode: _nombreFocus,
                            labelText: AppStrings.nombre,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FiscalTextField(
                            key: const ValueKey('fiscal_nif'),
                            controller: _nifController,
                            focusNode: _nifFocus,
                            labelText: 'NIF/CIF',
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FiscalTextField(
                            key: const ValueKey('fiscal_email'),
                            controller: _emailController,
                            focusNode: _emailFocus,
                            labelText: AppStrings.email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FiscalTextField(
                            key: const ValueKey('fiscal_phone'),
                            controller: _telefonoController,
                            focusNode: _telefonoFocus,
                            labelText: AppStrings.telefono,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: FiscalTextField(
                            key: const ValueKey('fiscal_address'),
                            controller: _direccionController,
                            focusNode: _direccionFocus,
                            labelText: AppStrings.direccion,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FiscalTextField(
                            key: const ValueKey('fiscal_city'),
                            controller: _ciudadController,
                            focusNode: _ciudadFocus,
                            labelText: AppStrings.ciudad,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: FiscalTextField(
                            key: const ValueKey('fiscal_iban'),
                            controller: _ibanController,
                            focusNode: _ibanFocus,
                            labelText: 'IBAN',
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                        const Spacer(flex: 3),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Guardar datos fiscales'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldBox({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
  }

  void _syncIfExternalChanged(AppSettings nextS) {
    if (_logoPath != nextS.logoPath) {
      _logoPath = nextS.logoPath;
    }
    _syncController(_nombreController, _nombreFocus, nextS.emisorNombre);
    _syncController(_nifController, _nifFocus, nextS.emisorNIF);
    _syncController(_emailController, _emailFocus, nextS.emisorEmail);
    _syncController(_telefonoController, _telefonoFocus, nextS.emisorTelefono);
    _syncController(
      _direccionController,
      _direccionFocus,
      nextS.emisorDireccion,
    );
    _syncController(_ciudadController, _ciudadFocus, nextS.emisorCiudad);
    _syncController(_ibanController, _ibanFocus, nextS.iban);
  }

  void _syncController(
    TextEditingController controller,
    FocusNode focusNode,
    String nextValue,
  ) {
    if (focusNode.hasFocus) return;
    if (controller.text == nextValue) return;
    final base = controller.selection.baseOffset.clamp(0, nextValue.length);
    final extent = controller.selection.extentOffset.clamp(0, nextValue.length);
    controller.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
      composing: TextRange.empty,
    );
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final destPath = '${dir.path}/logo.png';
    await File(image.path).copy(destPath);
    if (!mounted) return;
    setState(() => _logoPath = destPath);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSaved(
        _BillingFormData(
          logoPath: _logoPath,
          nombre: _nombreController.text.trim(),
          nif: _nifController.text.trim(),
          email: _emailController.text.trim(),
          telefono: _telefonoController.text.trim(),
          direccion: _direccionController.text.trim(),
          ciudad: _ciudadController.text.trim(),
          iban: _ibanController.text.trim(),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LogoSelector extends StatelessWidget {
  final String logoPath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _LogoSelector({
    required this.logoPath,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    Widget logoPreview = logoPath.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(logoPath),
              width: 100,
              height: 50,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 50),
            ),
          )
        : Container(
            width: 100,
            height: 50,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image, color: AppColors.textSecondary, size: 24),
                Text(
                  'Sin logo',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );

    Widget actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.photo_library, size: 18),
          label: const Text(
            'Seleccionar logo',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        if (logoPath.isNotEmpty) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: onRemove,
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.accentRed),
            ),
          ),
        ],
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 430;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: logoPreview),
                  const SizedBox(height: 12),
                  actions,
                ],
              );
            }
            return Row(
              children: [
                logoPreview,
                const SizedBox(width: 16),
                Expanded(child: actions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class FiscalTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String labelText;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;

  const FiscalTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.labelText,
    this.keyboardType,
    required this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        maxLines: 1,
        enableInteractiveSelection: true,
        scrollPadding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: keyboardInset + 120,
        ),
        onTap: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final textFieldContext = focusNode.context;
            if (textFieldContext == null) return;
            Scrollable.ensureVisible(
              textFieldContext,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: 0.35,
            );
          });
        },
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        decoration: InputDecoration(labelText: labelText),
      ),
    );
  }
}

// ── Cloud Sync Section ──

class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    final pendingCountAsync = ref.watch(syncQueuePendingCountProvider);
    final pendingCount = pendingCountAsync.valueOrNull ?? 0;
    // Usar el provider reactivo para el estado de autenticación
    final authState = ref.watch(supabaseAuthProvider);
    final isCloudAuth =
        authState.valueOrNull ?? SupabaseService.instance.isAuthenticated;
    final isSupported = PlatformAuthService.isSupported;

    final statusLabel = switch (syncState.status) {
      SyncStatus.syncing => 'Sincronizando cambios…',
      SyncStatus.error => 'No se pudieron sincronizar algunos datos',
      SyncStatus.success => 'Todo actualizado',
      SyncStatus.idle =>
        pendingCount > 0 ? 'Hay cambios pendientes' : 'Todo actualizado',
    };
    final safeMessage = _sanitizeSyncMessage(syncState.message);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isCloudAuth ? Icons.cloud_done : Icons.cloud_off,
                  color: isCloudAuth
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sincronización en la nube',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        isCloudAuth
                            ? 'Conectado: ${SupabaseService.instance.userEmail ?? ""}'
                            : 'No conectado',
                        style: TextStyle(
                          fontSize: 13,
                          color: isCloudAuth
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              statusLabel,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            if (isCloudAuth) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    pendingCount > 0 ? Icons.schedule : Icons.check_circle,
                    size: 16,
                    color: pendingCount > 0
                        ? AppColors.warning
                        : AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pendingCount > 0
                        ? '$pendingCount cambio${pendingCount == 1 ? '' : 's'} pendiente${pendingCount == 1 ? '' : 's'}'
                        : 'Sin cambios pendientes',
                    style: TextStyle(
                      fontSize: 12,
                      color: pendingCount > 0
                          ? AppColors.warning
                          : AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            if (!isCloudAuth && isSupported) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Conectar a la nube'),
                  onPressed: () async {
                    final success = await PlatformAuthService.instance.signIn();
                    if (success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Conectado a la nube')),
                      );
                    }
                  },
                ),
              ),
            ] else if (!isCloudAuth && !isSupported) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'La sincronización en la nube solo está disponible en iOS, Android y macOS.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              if (syncState.status == SyncStatus.syncing)
                const Center(child: CircularProgressIndicator())
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar ahora'),
                    onPressed: () => ref
                        .read(syncProvider.notifier)
                        .syncAll(reason: 'manual_button'),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PopupMenuButton<String>(
                    tooltip: 'Más opciones',
                    onSelected: (value) async {
                      final notifier = ref.read(syncProvider.notifier);
                      if (value == 'upload') {
                        await notifier.uploadToCloud(reason: 'manual_button');
                      } else if (value == 'download') {
                        await notifier.downloadFromCloud(
                          reason: 'manual_button',
                        );
                      } else if (value == 'conflicts') {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Si detectas datos inconsistentes, usa “Descargar” para refrescar desde nube.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'upload',
                        child: Text('Enviar cambios pendientes'),
                      ),
                      PopupMenuItem(
                        value: 'download',
                        child: Text('Actualizar desde la nube'),
                      ),
                      PopupMenuItem(
                        value: 'conflicts',
                        child: Text('Resolver conflictos'),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.divider),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune, size: 18),
                          SizedBox(width: 8),
                          Text('Más opciones'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Cerrar sesión (MisBolos)'),
                    onPressed: () => _signOut(context, ref),
                  ),
                ),
              ],

              // Estado de sincronización
              if (safeMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: syncState.status == SyncStatus.error
                        ? AppColors.errorBg
                        : syncState.status == SyncStatus.success
                        ? AppColors.successBg
                        : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        syncState.status == SyncStatus.error
                            ? Icons.error_outline
                            : syncState.status == SyncStatus.success
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 18,
                        color: syncState.status == SyncStatus.error
                            ? AppColors.error
                            : syncState.status == SyncStatus.success
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          safeMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: syncState.status == SyncStatus.error
                                ? AppColors.error
                                : syncState.status == SyncStatus.success
                                ? AppColors.success
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Última sincronización
              if (syncState.lastSync != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Última sincronización: ${_formatDate(syncState.lastSync!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Ahora mismo';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(authControllerProvider.notifier).signOut();
    if (!context.mounted) return;
    if (ok) {
      ref.invalidate(syncProvider);
      ref.invalidate(invoicesProvider);
      ref.invalidate(expensesProvider);
      ref.invalidate(assetsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión de MisBolos cerrada')),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No se pudo cerrar sesión')));
    }
  }

  String? _sanitizeSyncMessage(String? message) {
    if (message == null) return null;
    final lower = message.toLowerCase();
    if (lower.contains('failed host lookup') ||
        lower.contains('socketexception') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('timed out') ||
        lower.contains('https://') ||
        lower.contains('/rest/v1/')) {
      return 'Sin conexión a internet. Reintenta cuando vuelvas a estar conectado.';
    }
    return message;
  }
}
