import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/services/drive_backup_service.dart';
import '../../core/services/drive_document_sync_service.dart';
import '../../core/services/google_drive_service.dart';
import '../../models/app_settings.dart';
import '../../providers/assets_provider.dart';
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

  @override
  void dispose() {
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
              // ── Cuenta Google ──
              _GoogleSection(auth: googleAuth),
              const SizedBox(height: 16),

              // ── Archivo documental ──
              _buildGoogleDriveSection(settings),
              const SizedBox(height: 16),

              // ── Sincronización Cloud ──
              const _SyncSection(),
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

  Widget _buildGoogleDriveSection(AppSettings settings) {
    final connected = settings.driveConnected;
    final rootName = settings.driveRootFolderName;

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
                      Text(
                        connected
                            ? 'Archivo documental conectado'
                            : 'Backup documental sin configurar',
                        style: TextStyle(
                          fontSize: 13,
                          color: connected
                              ? AppColors.success
                              : AppColors.textSecondary,
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
            const SizedBox(height: 12),
            _driveInfoRow('Estado', connected ? 'Conectado' : 'No conectado'),
            _driveInfoRow(
              'Cuenta',
              settings.driveAccountEmail?.isNotEmpty == true
                  ? settings.driveAccountEmail!
                  : 'Sin cuenta conectada',
            ),
            _driveInfoRow(
              'Carpeta de trabajo',
              rootName?.isNotEmpty == true ? rootName! : 'Sin seleccionar',
            ),
            _driveInfoRow(
              'Último backup',
              _formatDriveDate(settings.lastDriveBackupAt),
            ),
            _driveInfoRow(
              'Última sincronización',
              _formatDriveDate(settings.lastDriveSyncAt),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _driveBusy ? null : _connectDrive,
                  icon: const Icon(Icons.login),
                  label: const Text('Conectar Google Drive'),
                ),
                OutlinedButton.icon(
                  onPressed: (!_driveBusy && settings.driveRootFolderId != null)
                      ? () => _openDriveFolder(settings.driveRootFolderId!)
                      : null,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ver carpeta'),
                ),
                OutlinedButton.icon(
                  onPressed: _driveBusy ? null : _disconnectDrive,
                  icon: const Icon(Icons.logout),
                  label: const Text('Desconectar'),
                ),
              ],
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
                  onPressed: (!_driveBusy && settings.driveRootFolderId != null)
                      ? () => _createDriveStructure(DateTime.now().year)
                      : null,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Crear estructura'),
                ),
                OutlinedButton.icon(
                  onPressed: (!_driveBusy && settings.driveRootFolderId != null)
                      ? _syncDriveDocuments
                      : null,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Sincronizar documentos'),
                ),
                OutlinedButton.icon(
                  onPressed: (!_driveBusy && settings.driveRootFolderId != null)
                      ? _retryPendingDriveSync
                      : null,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Reintentar pendientes'),
                ),
                OutlinedButton.icon(
                  onPressed: (!_driveBusy && settings.driveRootFolderId != null)
                      ? _createDriveBackupNow
                      : null,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Crear backup ahora'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<int>(
              future: DriveDocumentSyncService.instance.getPendingQueueCount(),
              builder: (context, snapshot) {
                final pending = snapshot.data ?? 0;
                return Text(
                  pending > 0
                      ? 'Pendientes Drive: $pending (máx ${DriveDocumentSyncService.maxRetryAttempts} intentos)'
                      : 'Sin pendientes en cola de Drive',
                  style: TextStyle(
                    fontSize: 12,
                    color: pending > 0
                        ? AppColors.warning
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
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

  Widget _driveInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDriveDate(DateTime? date) {
    if (date == null) return 'Sin datos';
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _connectDrive() async {
    await _runDriveAction(
      () async {
        await GoogleDriveService.instance.signIn();
        ref.invalidate(settingsProvider);
      },
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
      successMessage: 'Carpeta de trabajo seleccionada',
      errorPrefix: 'No se pudo seleccionar la carpeta',
    );
  }

  Future<void> _createDriveStructure(int year) async {
    await _runDriveAction(
      () async {
        await GoogleDriveService.instance.createFullYearStructure(year);
      },
      successMessage:
          'Estructura creada correctamente. Si ya existía, se ha reutilizado.',
      errorPrefix: 'No se pudo crear la estructura de Drive',
    );
  }

  Future<void> _openDriveFolder(String folderId) async {
    await _runDriveAction(() async {
      await GoogleDriveService.instance.openFolder(folderId);
    }, errorPrefix: 'No se pudo abrir la carpeta de Drive');
  }

  Future<void> _syncDriveDocuments() async {
    await _runDriveAction(() async {
      final result = await DriveDocumentSyncService.instance
          .syncExistingDocuments();
      ref.invalidate(settingsProvider);
      ref.invalidate(invoicesProvider);
      ref.invalidate(expensesProvider);
      ref.invalidate(assetsProvider);
      _showDriveMessage(
        'Documentos sincronizados: ${result.uploaded} subidos/actualizados, '
        '${result.skipped} omitidos, ${result.failed} pendientes.',
      );
    }, errorPrefix: 'No se pudo sincronizar documentos');
  }

  Future<void> _createDriveBackupNow() async {
    await _runDriveAction(() async {
      final result = await DriveBackupService.instance.createBackupNow();
      ref.invalidate(settingsProvider);
      _showDriveMessage('Backup creado correctamente: ${result.fileName}');
    }, errorPrefix: 'No se pudo crear el backup');
  }

  Future<void> _retryPendingDriveSync() async {
    await _runDriveAction(() async {
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
    }, errorPrefix: 'No se pudieron reintentar pendientes de Drive');
  }

  Future<void> _runDriveAction(
    Future<void> Function() action, {
    String? successMessage,
    required String errorPrefix,
  }) async {
    if (_driveBusy) return;
    setState(() => _driveBusy = true);
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
        setState(() => _driveBusy = false);
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
                'Conecta tu cuenta de Google',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sincroniza Google Calendar con tus bolos',
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
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.accentRed),
            title: const Text('Cerrar sesión de Google'),
            onTap: () => ref.read(googleAuthProvider.notifier).signOut(),
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
                        onPressed: () =>
                            ref.read(syncProvider.notifier).uploadToCloud(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_download, size: 18),
                        label: const Text('Descargar'),
                        onPressed: () =>
                            ref.read(syncProvider.notifier).downloadFromCloud(),
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
                    onPressed: () => ref.read(syncProvider.notifier).syncAll(),
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
}
