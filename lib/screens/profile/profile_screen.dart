import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/drive_document_sync_service.dart';
import '../../core/services/google_drive_service.dart';
import '../../models/app_settings.dart';
import '../../models/gig.dart';
import '../../providers/assets_provider.dart';
import '../../providers/auth_controller.dart';
import '../../providers/expenses_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../settings/duplicate_clients_screen.dart';
import '../settings/import_screen.dart';
import '../../services/google_auth_service.dart';
import '../../services/platform_auth_service.dart';
import '../../services/supabase_service.dart';

enum _StatusKind { ok, warn, error }

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nombreController = TextEditingController();
  final _nifController = TextEditingController();
  final _direccionController = TextEditingController();
  final _ciudadController = TextEditingController();
  final _provinciaController = TextEditingController();
  final _codigoPostalController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _ibanController = TextEditingController();
  final _driveSearchController = TextEditingController(text: 'MisBolos Test');
  String _logoPath = '';
  bool _loaded = false;
  List<DriveFolderResult> _driveFolderResults = [];
  bool _driveBusy = false;
  String _driveProgressLabel = '';
  double? _driveProgressValue;

  @override
  void initState() {
    super.initState();
    DriveDocumentSyncService.instance.progress.addListener(_handleDriveProgress);
  }

  @override
  void dispose() {
    DriveDocumentSyncService.instance.progress.removeListener(
      _handleDriveProgress,
    );
    _nombreController.dispose();
    _nifController.dispose();
    _direccionController.dispose();
    _ciudadController.dispose();
    _provinciaController.dispose();
    _codigoPostalController.dispose();
    _emailController.dispose();
    _telefonoController.dispose();
    _ibanController.dispose();
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

  void _loadSettings(AppSettings s) {
    if (_loaded) return;
    _loaded = true;
    _nombreController.text = s.emisorNombre;
    _nifController.text = s.emisorNIF;
    _direccionController.text = s.emisorDireccion;
    _ciudadController.text = s.emisorCiudad;
    _provinciaController.text = s.emisorProvincia;
    _codigoPostalController.text = s.emisorCodigoPostal;
    _emailController.text = s.emisorEmail;
    _telefonoController.text = s.emisorTelefono;
    _ibanController.text = s.iban;
    _logoPath = s.logoPath;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final googleAuth = ref.watch(googleAuthProvider);
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: AppStrings.ajustes,
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: settingsAsync.when(
        data: (settings) {
          _loadSettings(settings);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatusOverview(settings, googleAuth),
              const SizedBox(height: 16),

              _buildAccountSection(),
              const SizedBox(height: 16),

              // ── Archivo documental ──
              _buildGoogleDriveSection(settings),
              const SizedBox(height: 16),

              _buildCalendarSection(googleAuth),
              const SizedBox(height: 16),

              // ── Sincronización Cloud ──
              const _SyncSection(),
              if (syncState.message != null) const SizedBox(height: 8),
              const SizedBox(height: 24),

              _buildToolsSection(),
              const SizedBox(height: 24),

              // ── Logo ──
              Text(
                AppStrings.logo,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _LogoSelector(
                logoPath: _logoPath,
                onPick: _pickLogo,
                onRemove: () => setState(() => _logoPath = ''),
              ),
              const SizedBox(height: 24),

              // ── Datos de facturación ──
              Text(
                'Datos de facturación',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: AppStrings.nombre,
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nifController,
                decoration: const InputDecoration(
                  labelText: 'NIF / CIF',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _direccionController,
                decoration: const InputDecoration(
                  labelText: AppStrings.direccion,
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _ciudadController,
                decoration: const InputDecoration(
                  labelText: AppStrings.ciudad,
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _provinciaController,
                decoration: const InputDecoration(
                  labelText: 'Provincia',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _codigoPostalController,
                decoration: const InputDecoration(
                  labelText: 'Código Postal',
                  prefixIcon: Icon(Icons.markunread_mailbox_outlined),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: AppStrings.email,
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _telefonoController,
                decoration: const InputDecoration(
                  labelText: AppStrings.telefono,
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _ibanController,
                decoration: const InputDecoration(
                  labelText: 'IBAN',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(height: 24),

              // Guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text(AppStrings.guardar),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildStatusOverview(AppSettings settings, GoogleAuthState googleAuth) {
    final driveConnected = settings.driveConnected;
    final hasDriveFolder =
        (settings.driveRootFolderId?.trim().isNotEmpty ?? false) &&
        (settings.driveRootFolderName?.trim().isNotEmpty ?? false);
    final misBolosOk = SupabaseService.instance.isAuthenticated;
    final googleOk = googleAuth.isSignedIn;
    final driveOk = driveConnected && hasDriveFolder;
    final driveWarn = driveConnected && !hasDriveFolder;
    final calendarOk = googleAuth.calendarConnected;
    final calendarWarn = googleAuth.isSignedIn && !googleAuth.calendarConnected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _statusChip('MisBolos', misBolosOk ? _StatusKind.ok : _StatusKind.error),
            _statusChip('Google', googleOk ? _StatusKind.ok : _StatusKind.error),
            _statusChip(
              'Drive',
              driveOk
                  ? _StatusKind.ok
                  : driveWarn
                  ? _StatusKind.warn
                  : _StatusKind.error,
            ),
            _statusChip(
              'Calendar',
              calendarOk
                  ? _StatusKind.ok
                  : calendarWarn
                  ? _StatusKind.warn
                  : _StatusKind.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection() {
    final email = SupabaseService.instance.userEmail ?? 'Sin sesión activa';
    final connected = SupabaseService.instance.isAuthenticated;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cuenta',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              email,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  connected ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                  color: connected ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 8),
                Text(
                  connected ? 'Sesión de MisBolos activa' : 'Sesión cerrada',
                  style: TextStyle(
                    color: connected ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                    onPressed: () =>
                        ref.read(googleAuthProvider.notifier).connectCalendarOnly(),
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

  Widget _buildToolsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Herramientas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImportScreen()),
                ),
                icon: const Icon(Icons.upload_file),
                label: const Text('Importar Excel o CSV'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showExportWarning,
                icon: const Icon(Icons.download),
                label: const Text('Exportar CSV'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DuplicateClientsScreen(),
                  ),
                ),
                icon: const Icon(Icons.people_outline),
                label: const Text('Buscar clientes duplicados'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, _StatusKind kind) {
    final (bg, fg, icon) = switch (kind) {
      _StatusKind.ok => (AppColors.successBg, AppColors.success, Icons.check_circle),
      _StatusKind.warn => (AppColors.warningBg, AppColors.warning, Icons.warning_amber_rounded),
      _StatusKind.error => (AppColors.errorBg, AppColors.error, Icons.error_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv({required bool oficialOnly}) async {
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 100, 100);
    try {
      final gigs = await ref.read(gigsProvider.future);
      final invoices = await ref.read(invoicesProvider.future);
      final rows = <List<dynamic>>[
        ['Fecha', 'ClienteId', 'Caché', 'Facturable', 'Estado', 'Nº Factura'],
      ];
      for (final gig in gigs) {
        if (oficialOnly && !gig.facturable) continue;
        final inv = invoices.where((i) => i.gigId == gig.id).firstOrNull;
        rows.add([
          gig.fecha.toIso8601String().substring(0, 10),
          gig.facturable ? gig.clientId : 'PRIVADO',
          gig.cachet ?? 0,
          gig.facturable ? 'Sí' : 'No',
          gig.status.dbValue,
          inv?.numero ?? '',
        ]);
      }
      final csv = rows.map((r) => r.map((e) => '"$e"').join(',')).join('\n');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/misbolos_export.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error exportando CSV: $e')));
    }
  }

  void _showExportWarning() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exportar CSV'),
        content: const Text(
          '¿Quieres exportar solo bolos oficiales facturables o todos los datos?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportCsv(oficialOnly: true);
            },
            child: const Text('Solo oficiales'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportCsv(oficialOnly: false);
            },
            child: const Text('Todos'),
          ),
        ],
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
    final statusLabel = !connected
        ? 'Drive no conectado'
        : hasFolder
        ? 'Drive listo'
        : 'Falta seleccionar carpeta';
    final statusBg = !connected
        ? AppColors.errorBg
        : hasFolder
        ? AppColors.successBg
        : AppColors.warningBg;
    final statusFg = !connected
        ? AppColors.error
        : hasFolder
        ? AppColors.success
        : AppColors.warning;
    final statusIcon = !connected
        ? Icons.error_outline
        : hasFolder
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
                    connected
                        ? accountLabel
                        : 'Conecta Google Drive para activar la sincronización documental.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
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
                      ElevatedButton.icon(
                        onPressed: _driveBusy ? null : _searchDriveFolders,
                        icon: const Icon(Icons.folder_open),
                        label: Text(
                          hasFolder ? 'Cambiar carpeta' : 'Seleccionar carpeta',
                        ),
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
                OutlinedButton.icon(
                  onPressed: (!_driveBusy && driveReady)
                      ? _retryPendingDriveSync
                      : null,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Reintentar válidos'),
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
            const SizedBox(height: 6),
            FutureBuilder<List<Map<String, Object?>>>(
              future: DriveDocumentSyncService.instance.getRecentQueueErrors(),
              builder: (context, snapshot) {
                final rows = snapshot.data ?? const <Map<String, Object?>>[];
                if (rows.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows.take(3).map((row) {
                    final type = row['entity_type'] ?? '-';
                    final id = row['entity_id'] ?? '-';
                    final attempts = row['attempts'] ?? 0;
                    final err = row['last_error'] ?? 'Error desconocido';
                    return Text(
                      '• $type/$id (intentos: $attempts): $err',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            FutureBuilder<DriveQueueSummary>(
              future: DriveDocumentSyncService.instance.getQueueSummary(),
              builder: (context, snapshot) {
                final s = snapshot.data ?? const DriveQueueSummary();
                if (s.lastError == null || s.lastError!.trim().isEmpty) {
                  return const SizedBox.shrink();
                }
                return Text(
                  'Último error Drive: ${s.lastError}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                );
              },
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
        ref.invalidate(settingsProvider);
      },
      progressLabel: 'Conectando cuenta de Google Drive...',
      successMessage: 'Google Drive conectado',
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
      if (mounted && successMessage != null) {
        _showDriveMessage(successMessage);
      }
    } catch (e) {
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

  void _showDriveMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final destPath = '${dir.path}/logo.png';
    await File(image.path).copy(destPath);

    setState(() => _logoPath = destPath);
  }

  Future<void> _save() async {
    // Preserve settings that aren't edited here
    final current = await ref.read(settingsProvider.future);
    final settings = current.copyWith(
      logoPath: _logoPath,
      emisorNombre: _nombreController.text.trim(),
      emisorNIF: _nifController.text.trim(),
      emisorDireccion: _direccionController.text.trim(),
      emisorCiudad: _ciudadController.text.trim(),
      emisorProvincia: _provinciaController.text.trim(),
      emisorCodigoPostal: _codigoPostalController.text.trim(),
      emisorEmail: _emailController.text.trim(),
      emisorTelefono: _telefonoController.text.trim(),
      iban: _ibanController.text.trim(),
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
      } catch (_) {
        // Local settings are the source of truth; cloud sync can be retried later.
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Perfil guardado')));
    }
  }
}

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (logoPath.isNotEmpty)
              ClipRRect(
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
            else
              Container(
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
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.photo_library, size: 18),
                    label: const Text('Seleccionar logo'),
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
              ),
            ),
          ],
        ),
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
            const SizedBox(height: 12),
            const Text(
              'Sincroniza todos tus datos entre dispositivos.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
                        ? '$pendingCount cambio${pendingCount == 1 ? '' : 's'} pendiente${pendingCount == 1 ? '' : 's'} de sincronizar'
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
              // Botones de sincronización
              if (syncState.status == SyncStatus.syncing)
                const Center(child: CircularProgressIndicator())
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_upload, size: 18),
                        label: const Text('Subir'),
                        onPressed: () => ref
                            .read(syncProvider.notifier)
                            .uploadToCloud(reason: 'manual_button'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_download, size: 18),
                        label: const Text('Descargar'),
                        onPressed: () => ref
                            .read(syncProvider.notifier)
                            .downloadFromCloud(reason: 'manual_button'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar todo'),
                    onPressed: () => ref
                        .read(syncProvider.notifier)
                        .syncAll(reason: 'manual_button'),
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
              if (syncState.message != null) ...[
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
                          syncState.message!,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(content: Text('Sesión de MisBolos cerrada')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cerrar sesión')),
      );
    }
  }
}
