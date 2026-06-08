import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../../models/app_settings.dart';
import '../../models/gig.dart';
import '../../models/pdf_theme.dart';
import '../../providers/gig_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/supabase_service.dart';
import '../settings/duplicate_clients_screen.dart';
import '../settings/import_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _ivaDefault = 0.21;
  double _irpfDefault = 0.15;
  double _logoSize = 180;
  String _pdfTheme = 'clasico';
  bool _notificaciones = true;
  int _diasRecordatorio = 7;
  bool _emailInvoiceRemindersEnabled = false;
  String _invoiceReminderFrequency = 'weekly';
  bool _autoCloudSyncEnabled = true;
  int _autoCloudSyncIntervalSeconds = 45;
  String _appThemeMode = 'light';
  bool _securityPinEnabled = false;
  String _securityPinCode = '';
  bool _securityBiometricEnabled = false;
  bool _verifactuEnabled = false;
  int _lockDelaySeconds = 5;
  bool _loaded = false;

  void _loadSettings(AppSettings s) {
    if (_loaded) return;
    _loaded = true;
    _ivaDefault = s.ivaDefault;
    _irpfDefault = s.irpfDefault;
    _logoSize = s.logoSize;
    _pdfTheme = s.pdfTheme;
    _notificaciones = s.notificacionesActivas;
    _diasRecordatorio = s.diasRecordatorio;
    _emailInvoiceRemindersEnabled = s.emailInvoiceRemindersEnabled;
    _invoiceReminderFrequency = s.invoiceReminderFrequency;
    _autoCloudSyncEnabled = s.autoCloudSyncEnabled;
    _autoCloudSyncIntervalSeconds = s.autoCloudSyncIntervalSeconds;
    _appThemeMode = s.appThemeMode;
    _securityPinEnabled = s.securityPinEnabled;
    _securityPinCode = s.securityPinCode;
    _securityBiometricEnabled = s.securityBiometricEnabled;
    _verifactuEnabled = s.verifactuEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: settingsAsync.when(
        data: (settings) {
          _loadSettings(settings);
          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildAppearanceCard()),
                              const SizedBox(width: 12),
                              Expanded(child: _buildSyncCard()),
                            ],
                          )
                        else ...[
                          _buildAppearanceCard(),
                          const SizedBox(height: 12),
                          _buildSyncCard(),
                        ],
                        const SizedBox(height: 12),
                        _buildRemindersCard(settings),
                        const SizedBox(height: 12),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildSecurityCard()),
                              const SizedBox(width: 12),
                              Expanded(child: _buildPdfCard()),
                            ],
                          )
                        else ...[
                          _buildSecurityCard(),
                          const SizedBox(height: 12),
                          _buildPdfCard(),
                        ],
                        const SizedBox(height: 12),
                        _buildAdvancedCard(),
                        const SizedBox(height: 18),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'Tus datos se sincronizan de forma segura y privada.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _sectionCard(String title, IconData icon, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceCard() {
    return _sectionCard(
      'Apariencia',
      Icons.palette_outlined,
      Column(
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'light', label: Text('Claro')),
              ButtonSegment(value: 'dark', label: Text('Oscuro')),
              ButtonSegment(value: 'system', label: Text('Sistema')),
            ],
            selected: {_appThemeMode},
            onSelectionChanged: (v) async {
              setState(() => _appThemeMode = v.first);
              await _saveInstant();
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'El tema se aplica al instante.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard() {
    return _sectionCard(
      'Sincronización',
      Icons.sync,
      Column(
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-sync'),
            subtitle: const Text('Sincronización automática en segundo plano'),
            value: _autoCloudSyncEnabled,
            onChanged: (v) async {
              setState(() => _autoCloudSyncEnabled = v);
              await _saveInstant();
            },
          ),
          if (_autoCloudSyncEnabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Frecuencia de sync'),
              trailing: DropdownButton<int>(
                value: _autoCloudSyncIntervalSeconds,
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 s')),
                  DropdownMenuItem(value: 45, child: Text('45 s')),
                  DropdownMenuItem(value: 60, child: Text('1 min')),
                  DropdownMenuItem(value: 120, child: Text('2 min')),
                  DropdownMenuItem(value: 300, child: Text('5 min')),
                ],
                onChanged: (v) async {
                  setState(() => _autoCloudSyncIntervalSeconds = v ?? 45);
                  await _saveInstant();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRemindersCard(AppSettings settings) {
    final accountEmail =
        SupabaseService.instance.userEmail?.trim().isNotEmpty == true
        ? SupabaseService.instance.userEmail!.trim()
        : settings.emisorEmail.trim();
    final canUseEmailReminders =
        SupabaseService.instance.isAuthenticated && accountEmail.isNotEmpty;
    final emailSubtitle = canUseEmailReminders
        ? 'Recibe un correo con tus facturas pendientes.'
        : 'Inicia sesión y configura un email para activar recordatorios por correo.';

    return _sectionCard(
      'Recordatorios',
      Icons.notifications_active_outlined,
      Column(
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Recordatorios en la app'),
            subtitle: const Text(
              'Recibe avisos dentro de MisBolos sobre facturas pendientes.',
            ),
            value: _notificaciones,
            onChanged: (v) async {
              setState(() => _notificaciones = v);
              await _saveInstant();
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Recordatorios por email'),
            subtitle: Text(emailSubtitle),
            value: canUseEmailReminders && _emailInvoiceRemindersEnabled,
            onChanged: canUseEmailReminders
                ? (v) async {
                    setState(() => _emailInvoiceRemindersEnabled = v);
                    await _saveInstant();
                  }
                : null,
          ),
          if (_emailInvoiceRemindersEnabled && canUseEmailReminders)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Frecuencia de recordatorios'),
              subtitle: const Text(
                'Recibirás un resumen de tus facturas pendientes según la frecuencia seleccionada.',
              ),
              trailing: DropdownButton<String>(
                value: _invoiceReminderFrequency,
                items: const [
                  DropdownMenuItem(value: 'weekly', child: Text('Cada 7 días')),
                  DropdownMenuItem(
                    value: 'biweekly',
                    child: Text('Cada 15 días'),
                  ),
                  DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
                ],
                onChanged: (v) async {
                  setState(() => _invoiceReminderFrequency = v ?? 'weekly');
                  await _saveInstant();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSecurityCard() {
    return _sectionCard(
      'Seguridad',
      Icons.shield_outlined,
      Column(
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Bloqueo con PIN'),
            subtitle: const Text('Solicitar PIN al desbloquear la app'),
            value: _securityPinEnabled,
            onChanged: (v) async {
              setState(() {
                _securityPinEnabled = v;
                if (!v) _securityPinCode = '';
              });
              await _saveInstant();
            },
          ),
          if (_securityPinEnabled)
            TextFormField(
              initialValue: _securityPinCode,
              decoration: const InputDecoration(
                labelText: 'PIN (4-8 dígitos)',
                hintText: 'Ejemplo: 1234',
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              onChanged: (v) => _securityPinCode = v,
              onFieldSubmitted: (_) async => _saveInstant(),
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Bloqueo biométrico'),
            subtitle: const Text('Touch ID / Face ID según dispositivo'),
            value: _securityBiometricEnabled,
            onChanged: (v) async {
              setState(() => _securityBiometricEnabled = v);
              await _saveInstant();
            },
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Tiempo antes de bloqueo'),
            subtitle: Text('$_lockDelaySeconds segundos'),
            trailing: DropdownButton<int>(
              value: _lockDelaySeconds,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Inmediato')),
                DropdownMenuItem(value: 5, child: Text('5 s')),
                DropdownMenuItem(value: 15, child: Text('15 s')),
                DropdownMenuItem(value: 30, child: Text('30 s')),
              ],
              onChanged: (v) {
                setState(() => _lockDelaySeconds = v ?? 5);
                _showUpdated();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfCard() {
    return _sectionCard(
      'Facturación',
      Icons.receipt_long_outlined,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 700;
              final iva = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'IVA por defecto',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 0.21, label: Text('21%')),
                      ButtonSegment(value: 0.10, label: Text('10%')),
                      ButtonSegment(value: 0.0, label: Text('0%')),
                    ],
                    selected: {_ivaDefault},
                    onSelectionChanged: (v) =>
                        setState(() => _ivaDefault = v.first),
                  ),
                ],
              );
              final irpf = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Retención IRPF por defecto',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 0.0, label: Text('0%')),
                      ButtonSegment(value: 0.07, label: Text('7%')),
                      ButtonSegment(value: 0.15, label: Text('15%')),
                      ButtonSegment(value: 0.19, label: Text('19%')),
                    ],
                    selected: {_irpfDefault},
                    onSelectionChanged: (v) =>
                        setState(() => _irpfDefault = v.first),
                  ),
                ],
              );

              if (!sideBySide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [iva, const SizedBox(height: 12), irpf],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: iva),
                  const SizedBox(width: 12),
                  Expanded(child: irpf),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Activar modo VeriFactu'),
            subtitle: const Text(
              'Aplica reglas fiscales estrictas sobre las facturas emitidas.',
            ),
            value: _verifactuEnabled,
            onChanged: (value) async {
              if (value) {
                final confirmed = await _confirmEnableVerifactu();
                if (confirmed != true) return;
              }
              setState(() => _verifactuEnabled = value);
              await _saveInstant();
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Tamaño del logo',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            value: _logoSize,
            min: 10,
            max: 300,
            divisions: 29,
            label: '${_logoSize.round()}pt',
            onChanged: (v) => setState(() => _logoSize = v),
          ),
          const SizedBox(height: 8),
          Text('Plantilla PDF', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: PdfTheme.values.map((theme) {
              final isSelected = _pdfTheme == theme.name;
              final color = _pdfThemeColor(theme);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _pdfTheme = theme.name),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 6, width: 90, color: color),
                      const SizedBox(height: 8),
                      Container(
                        height: 4,
                        width: 120,
                        color: color.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        height: 4,
                        width: 80,
                        color: color.withValues(alpha: 0.35),
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          color: color,
                          child: Text(
                            theme.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _buildThemePreview(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saveComplex,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar configuración PDF'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedCard() {
    return _sectionCard(
      'Avanzado',
      Icons.tune,
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Herramientas técnicas'),
        subtitle: const Text('Importación y utilidades de mantenimiento'),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Importar Excel o CSV'),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Exportar CSV'),
            onTap: _showExportWarning,
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Buscar clientes duplicados'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DuplicateClientsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.broken_image_outlined),
            title: const Text('Reparar adjuntos y limpiar inválidos'),
            onTap: () => context.push('/attachments/broken'),
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
      await Share.shareXFiles([
        XFile(file.path),
      ], sharePositionOrigin: shareOrigin);
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

  Future<void> _saveInstant() async {
    final pin = _securityPinCode.trim();
    if (_securityPinEnabled && !RegExp(r'^\\d{4,8}$').hasMatch(pin)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El PIN debe tener entre 4 y 8 dígitos numéricos.'),
          ),
        );
      }
      return;
    }
    final current = await ref.read(settingsProvider.future);
    final accountEmail =
        SupabaseService.instance.userEmail?.trim().isNotEmpty == true
        ? SupabaseService.instance.userEmail!.trim()
        : current.emisorEmail.trim();
    final canUseEmailReminders =
        SupabaseService.instance.isAuthenticated && accountEmail.isNotEmpty;
    final settings = current.copyWith(
      notificacionesActivas: _notificaciones,
      diasRecordatorio: _diasRecordatorio,
      emailInvoiceRemindersEnabled:
          canUseEmailReminders && _emailInvoiceRemindersEnabled,
      invoiceReminderFrequency: _invoiceReminderFrequency,
      autoCloudSyncEnabled: _autoCloudSyncEnabled,
      autoCloudSyncIntervalSeconds: _autoCloudSyncIntervalSeconds,
      appThemeMode: _appThemeMode,
      securityPinEnabled: _securityPinEnabled,
      securityPinCode: pin,
      securityBiometricEnabled: _securityBiometricEnabled,
      verifactuEnabled: _verifactuEnabled,
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
    _showUpdated();
  }

  Future<void> _saveComplex() async {
    final current = await ref.read(settingsProvider.future);
    final settings = current.copyWith(
      ivaDefault: _ivaDefault,
      irpfDefault: _irpfDefault,
      logoSize: _logoSize,
      pdfTheme: _pdfTheme,
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
    _showUpdated();
  }

  void _showUpdated() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Preferencia actualizada')));
  }

  Future<bool?> _confirmEnableVerifactu() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Activar modo VeriFactu'),
        content: const Text(
          'Al activar este modo, las facturas emitidas quedarán bloqueadas y no podrán editarse ni eliminarse. Para corregir una factura tendrás que crear una factura rectificativa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
  }

  Color _pdfThemeColor(PdfTheme theme) {
    switch (theme) {
      case PdfTheme.clasico:
        return const Color(0xFF1B2A4A);
      case PdfTheme.moderno:
        return const Color(0xFF2D2D2D);
      case PdfTheme.corporativo:
        return const Color(0xFF0066CC);
      case PdfTheme.elegante:
        return const Color(0xFF6B4C9A);
      case PdfTheme.natural:
        return const Color(0xFF2E7D32);
      case PdfTheme.calido:
        return const Color(0xFF8B4513);
    }
  }

  Color _pdfThemeRowAlt(PdfTheme theme) {
    switch (theme) {
      case PdfTheme.clasico:
        return const Color(0xFFF5F6FA);
      case PdfTheme.moderno:
        return const Color(0xFFF0F0F0);
      case PdfTheme.corporativo:
        return const Color(0xFFE6F0FA);
      case PdfTheme.elegante:
        return const Color(0xFFF3EFF8);
      case PdfTheme.natural:
        return const Color(0xFFE8F5E9);
      case PdfTheme.calido:
        return const Color(0xFFFFF8E1);
    }
  }

  Widget _buildThemePreview() {
    final theme = PdfTheme.fromName(_pdfTheme);
    final primaryColor = _pdfThemeColor(theme);
    final rowAltColor = _pdfThemeRowAlt(theme);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'FACTURA',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(color: Colors.grey.shade300, thickness: 1),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Container(height: 10, color: rowAltColor)),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 10, color: rowAltColor)),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 8, color: primaryColor),
        ],
      ),
    );
  }
}
