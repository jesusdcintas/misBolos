import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../models/app_settings.dart';
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
  String _logoPath = '';
  bool _loaded = false;

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

              // ── Sincronización Cloud ──
              const _SyncSection(),
              const SizedBox(height: 24),

              // ── Logo ──
              Text(AppStrings.logo,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 12),
              _LogoSelector(
                logoPath: _logoPath,
                onPick: _pickLogo,
                onRemove: () => setState(() => _logoPath = ''),
              ),
              const SizedBox(height: 24),

              // ── Datos de facturación ──
              Text('Datos de facturación',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
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
    final settings = AppSettings(
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
      ivaDefault: current.ivaDefault,
      notificacionesActivas: current.notificacionesActivas,
      diasRecordatorio: current.diasRecordatorio,
    );

    await ref.read(settingsProvider.notifier).save(settings);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil guardado')),
      );
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
              const Icon(Icons.account_circle, size: 64, color: AppColors.textSecondary),
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
                  onPressed: () => ref.read(googleAuthProvider.notifier).signIn(),
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
              leading:
                  Icon(Icons.calendar_month, color: AppColors.primary),
              title: Text('Google Calendar'),
              subtitle: Text('Bolos sincronizados'),
              trailing: Icon(Icons.check_circle,
                  color: AppColors.accentGreen, size: 20),
            )
          else
            ListTile(
              leading: const Icon(Icons.calendar_month,
                  color: Colors.orange),
              title: const Text('Google Calendar'),
              subtitle: const Text('Sin sincronizar · Toca para conectar'),
              trailing: const Icon(Icons.warning_amber_rounded,
                  color: Colors.orange, size: 20),
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
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
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
                    Text('Sin logo', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
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
                      child: const Text('Eliminar', style: TextStyle(color: AppColors.accentRed)),
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
    // Usar el provider reactivo para el estado de autenticación
    final authState = ref.watch(supabaseAuthProvider);
    final isCloudAuth = authState.valueOrNull ?? SupabaseService.instance.isAuthenticated;
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
                  color: isCloudAuth ? AppColors.success : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sincronización en la nube',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        isCloudAuth 
                          ? 'Conectado: ${SupabaseService.instance.userEmail ?? ""}' 
                          : 'No conectado',
                        style: TextStyle(
                          fontSize: 13, 
                          color: isCloudAuth ? AppColors.success : AppColors.textSecondary,
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
                    Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'La sincronización en la nube solo está disponible en iOS, Android y macOS.',
                        style: TextStyle(fontSize: 13, color: AppColors.warning),
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
                        onPressed: () => ref.read(syncProvider.notifier).uploadToCloud(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_download, size: 18),
                        label: const Text('Descargar'),
                        onPressed: () => ref.read(syncProvider.notifier).downloadFromCloud(),
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
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
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
