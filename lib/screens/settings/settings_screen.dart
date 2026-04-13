import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../models/app_settings.dart';
import '../../models/gig.dart';
import '../../models/pdf_theme.dart';
import '../../providers/settings_provider.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../services/supabase_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'import_screen.dart';
import 'duplicate_clients_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _ivaDefault = 0.21;
  double _logoSize = 180;
  String _pdfTheme = 'clasico';
  bool _notificaciones = true;
  int _diasRecordatorio = 7;
  bool _loaded = false;

  @override
  void dispose() {
    super.dispose();
  }

  void _loadSettings(AppSettings s) {
    if (_loaded) return;
    _loaded = true;
    _ivaDefault = s.ivaDefault;
    _logoSize = s.logoSize;
    _pdfTheme = s.pdfTheme;
    _notificaciones = s.notificacionesActivas;
    _diasRecordatorio = s.diasRecordatorio;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.ajustes)),
      body: settingsAsync.when(
        data: (settings) {
          _loadSettings(settings);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // IVA
              Text(AppStrings.ivaPorDefecto,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
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
              const SizedBox(height: 24),

              // Tamaño logo
              Text('Tamaño del logo en PDF',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('10'),
                  Expanded(
                    child: Slider(
                      value: _logoSize,
                      min: 10,
                      max: 300,
                      divisions: 29,
                      label: '${_logoSize.round()}pt',
                      onChanged: (v) => setState(() => _logoSize = v),
                    ),
                  ),
                  const Text('300'),
                ],
              ),
              Center(
                child: Text(
                  '${_logoSize.round()}pt',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: 24),

              // Tema PDF
              Text('Tema de color del PDF',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                childAspectRatio: 1.5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: PdfTheme.values.map((theme) {
                  final isSelected = _pdfTheme == theme.name;
                  final color = _pdfThemeColor(theme);
                  return GestureDetector(
                    onTap: () => setState(() => _pdfTheme = theme.name),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isSelected)
                            const Icon(Icons.check, color: Colors.white, size: 20),
                          Text(
                            theme.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Preview del tema
              _buildThemePreview(),
              const SizedBox(height: 24),

              // Notificaciones
              Text(AppStrings.notificaciones,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              SwitchListTile(
                title: const Text('Activar recordatorios'),
                value: _notificaciones,
                onChanged: (v) => setState(() => _notificaciones = v),
              ),
              if (_notificaciones)
                ListTile(
                  title: const Text(AppStrings.diasRecordatorio),
                  trailing: DropdownButton<int>(
                    value: _diasRecordatorio,
                    items: [3, 5, 7, 10, 14, 30]
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text('$d días'),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _diasRecordatorio = v ?? 7),
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
              const SizedBox(height: 32),

              // Sincronización
              Text('Sincronización',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _syncSupabase,
                icon: const Icon(Icons.sync),
                label: const Text(AppStrings.sincronizar),
              ),
              const SizedBox(height: 24),

              // Exportar CSV
              Text(AppStrings.exportarCSV,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _exportCsv(oficialOnly: true),
                      child: const Text('Solo oficiales'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showExportWarning(),
                      child: const Text('Todos los datos'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Importar historial
              Text('Importar historial',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ImportScreen()),
                  ),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Importar desde Excel o CSV'),
                ),
              ),
              const SizedBox(height: 24),

              // Herramientas
              Text('Herramientas',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DuplicateClientsScreen()),
                  ),
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Buscar clientes duplicados'),
                ),
              ),
              const SizedBox(height: 32),

              // Aviso legal
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.purpleBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.purple.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: AppColors.purple, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppStrings.avisoLegal,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.purple,
                        ),
                      ),
                    ),
                  ],
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

  Future<void> _save() async {
    // Preserve profile fields that are edited in ProfileScreen
    final current = await ref.read(settingsProvider.future);
    final settings = current.copyWith(
      ivaDefault: _ivaDefault,
      logoSize: _logoSize,
      pdfTheme: _pdfTheme,
      notificacionesActivas: _notificaciones,
      diasRecordatorio: _diasRecordatorio,
    );

    await ref.read(settingsProvider.notifier).save(settings);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajustes guardados')),
      );
    }
  }

  Future<void> _syncSupabase() async {
    try {
      final service = SupabaseService.instance;
      if (!service.isAuthenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No estás autenticado en la nube')),
          );
        }
        return;
      }

      final clients = await ref.read(clientsProvider.future);
      final gigs = await ref.read(gigsProvider.future);
      final invoices = await ref.read(invoicesProvider.future);

      await service.uploadAll(
        clients: clients,
        gigs: gigs,
        invoices: invoices,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sincronización completada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de sincronización: $e')),
        );
      }
    }
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
          gig.status.label,
          inv?.numero ?? '',
        ]);
      }

      final csv =
          rows.map((r) => r.map((e) => '"$e"').join(',')).join('\n');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/misbolos_export.csv');
      await file.writeAsString(csv);

      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showExportWarning() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Atención'),
        content: const Text(
          'Esta exportación incluirá datos de bolos no facturados. '
          'Los nombres de clientes se ocultarán en estos registros.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancelar),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _exportCsv(oficialOnly: false);
            },
            child: const Text('Exportar'),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header simulado
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
          
          // Info simulada
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('EMISOR', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: primaryColor)),
                    Container(height: 4, width: 50, color: Colors.grey.shade300, margin: const EdgeInsets.only(top: 2)),
                    Container(height: 4, width: 40, color: Colors.grey.shade300, margin: const EdgeInsets.only(top: 2)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FACTURAR A', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: primaryColor)),
                    Container(height: 4, width: 50, color: Colors.grey.shade300, margin: const EdgeInsets.only(top: 2)),
                    Container(height: 4, width: 40, color: Colors.grey.shade300, margin: const EdgeInsets.only(top: 2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          // Tabla simulada
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Column(
              children: [
                // Header de tabla
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(1)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 1, child: Text('Cant.', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text('Descripción', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('Precio', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                    ],
                  ),
                ),
                // Filas
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                  color: Colors.white,
                  child: Row(
                    children: [
                      const Expanded(flex: 1, child: Text('1', style: TextStyle(fontSize: 7))),
                      const Expanded(flex: 3, child: Text('Servicio DJ', style: TextStyle(fontSize: 7))),
                      Expanded(flex: 2, child: Text('500,00 €', style: const TextStyle(fontSize: 7), textAlign: TextAlign.right)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
                  color: rowAltColor,
                  child: Row(
                    children: [
                      const Expanded(flex: 1, child: Text('2', style: TextStyle(fontSize: 7))),
                      const Expanded(flex: 3, child: Text('Desplazamiento', style: TextStyle(fontSize: 7))),
                      Expanded(flex: 2, child: Text('50,00 €', style: const TextStyle(fontSize: 7), textAlign: TextAlign.right)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          
          // Total
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Text(
                'TOTAL  665,50 €',
                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
