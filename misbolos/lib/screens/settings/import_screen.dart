import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../services/import_service.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  int _currentStep = 0;

  // Step 1: file data
  String? _fileName;
  List<List<String>> _rows = [];
  List<ImportColumn> _columns = [];
  String _csvSeparator = ',';
  bool _isCsv = false;

  // Step 2: mapping
  Map<int, ColumnRole> _columnRoles = {};

  // Step 3: config
  int _year = DateTime.now().year - 1;
  ImportDefaultStatus _defaultStatus = ImportDefaultStatus.cobrado;
  bool _createClients = true;

  // Step 4: preview
  ImportPreview? _preview;
  bool _loadingPreview = false;

  // Step 5: importing
  bool _importing = false;
  int _progressCurrent = 0;
  int _progressTotal = 0;
  ImportResult? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar historial'),
        actions: [
          IconButton(
            tooltip: 'Reparar XLSX',
            onPressed: _showXlsxRepairDialog,
            icon: const Icon(Icons.build_circle_outlined),
          ),
        ],
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: _buildControls,
        steps: [
          Step(
            title: const Text('Seleccionar archivo'),
            content: _buildStep1(),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Mapear columnas'),
            content: _buildStep2(),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Configurar importación'),
            content: _buildStep3(),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Preview'),
            content: _buildStep4(),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Importar'),
            content: _buildStep5(),
            isActive: _currentStep >= 4,
            state: _result != null && _result!.error == null
                ? StepState.complete
                : StepState.indexed,
          ),
        ],
      ),
    );
  }

  // ─── Step 1: Select file ───────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.file_open),
          label: const Text('Seleccionar Excel o CSV'),
        ),
        if (_fileName != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _fileName!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        if (_isCsv && _rows.isEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Separador del CSV:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: ',', label: Text('Coma (,)')),
              ButtonSegment(value: ';', label: Text('Punto y coma (;)')),
              ButtonSegment(value: '\t', label: Text('Tabulador')),
            ],
            selected: {_csvSeparator},
            onSelectionChanged: (v) => setState(() => _csvSeparator = v.first),
          ),
        ],
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${_rows.length - 1} filas detectadas · ${_columns.length} columnas',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _buildPreviewTable(),
        ],
      ],
    );
  }

  Widget _buildPreviewTable() {
    final previewRows = _rows.take(6).toList();
    if (previewRows.isEmpty) return const SizedBox();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 36,
        columnSpacing: 16,
        columns: _columns
            .map(
              (c) => DataColumn(
                label: Text(
                  c.header,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
            .toList(),
        rows: previewRows.skip(1).map((row) {
          return DataRow(
            cells: _columns.map((c) {
              final value = c.index < row.length ? row[c.index] : '';
              return DataCell(
                Text(value, style: const TextStyle(fontSize: 11)),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  // ─── Step 2: Map columns ───────────────────────────────

  Widget _buildStep2() {
    if (_columns.isEmpty) {
      return const Text('Selecciona un archivo primero');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Asigna cada columna a su tipo de dato:',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        ..._columns.map(
          (col) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        col.header,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (col.sampleValues.isNotEmpty)
                        Text(
                          col.sampleValues.first,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<ColumnRole>(
                    initialValue: _columnRoles[col.index] ?? ColumnRole.ignorar,
                    isDense: true,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    items: ColumnRole.values
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(
                              role.label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (role) {
                      if (role != null) {
                        setState(() {
                          // Remove this role from any other column
                          if (role != ColumnRole.ignorar) {
                            _columnRoles.removeWhere(
                              (k, v) => v == role && k != col.index,
                            );
                          }
                          _columnRoles[col.index] = role;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!_hasFechaAndCliente) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Debes asignar al menos Fecha y Cliente',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  bool get _hasFechaAndCliente =>
      _columnRoles.values.contains(ColumnRole.fecha) &&
      _columnRoles.values.contains(ColumnRole.cliente);

  // ─── Step 3: Config ────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Año de los datos',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _year,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: List.generate(
            10,
            (i) => DateTime.now().year - i,
          ).map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
          onChanged: (v) => setState(() => _year = v ?? _year),
        ),
        const SizedBox(height: 16),
        const Text(
          'Estado de los bolos importados',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ImportDefaultStatus>(
          segments: ImportDefaultStatus.values
              .map((s) => ButtonSegment(value: s, label: Text(s.label)))
              .toList(),
          selected: {_defaultStatus},
          onSelectionChanged: (v) => setState(() => _defaultStatus = v.first),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Crear clientes automáticamente'),
          subtitle: const Text(
            'Si el venue no existe, se crea como cliente nuevo',
            style: TextStyle(fontSize: 12),
          ),
          value: _createClients,
          onChanged: (v) => setState(() => _createClients = v),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.successBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_done_outlined,
                color: AppColors.success,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Todos los bolos importados, incluidos los eventos privados, se sincronizan con Supabase. Solo tú puedes acceder a ellos.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Step 4: Preview ───────────────────────────────────

  Widget _buildStep4() {
    if (_loadingPreview) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_preview == null) {
      return const Text('Cargando preview...');
    }

    final p = _preview!;
    final dateFormat = DateFormat('MMM yyyy', 'es');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Listo para importar',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Divider(height: 24),
          _summaryRow('Bolos facturables', '${p.bolosFacturables}'),
          _summaryRow('Eventos privados', '${p.bolosEnB}'),
          _summaryRow('Clientes nuevos', '${p.clientesNuevos}'),
          _summaryRow(
            'Total importe',
            CurrencyFormatter.format(p.totalImporte),
          ),
          if (p.fechaMin != null && p.fechaMax != null)
            _summaryRow(
              'Período',
              '${dateFormat.format(p.fechaMin!)} — ${dateFormat.format(p.fechaMax!)}',
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ─── Step 5: Import ────────────────────────────────────

  Widget _buildStep5() {
    if (_importing) {
      final progress = _progressTotal > 0
          ? _progressCurrent / _progressTotal
          : 0.0;
      return Column(
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text('Importando $_progressCurrent de $_progressTotal...'),
        ],
      );
    }

    if (_result != null) {
      final r = _result!;
      if (r.error != null) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.error, color: AppColors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(r.error!, style: TextStyle(color: AppColors.error)),
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.successBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 48),
            const SizedBox(height: 12),
            Text(
              '${r.imported} bolos importados correctamente',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.success,
              ),
            ),
            if (r.skipped > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${r.skipped} ya existían',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            if (r.clientsCreated > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${r.clientsCreated} clientes nuevos creados',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ],
        ),
      );
    }

    return const Text('Pulsa "Importar" para comenzar.');
  }

  // ─── Controls ──────────────────────────────────────────

  Widget _buildControls(BuildContext context, ControlsDetails details) {
    // Don't show controls on step 5 after result
    if (_currentStep == 4 &&
        (_importing || (_result != null && _result!.error == null))) {
      if (_result != null && _result!.error == null) {
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ),
        );
      }
      return const SizedBox();
    }

    final isLastStep = _currentStep == 4;
    final canContinue = _canContinue();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: canContinue ? details.onStepContinue : null,
              style: isLastStep
                  ? ElevatedButton.styleFrom(backgroundColor: AppColors.success)
                  : null,
              child: Text(isLastStep ? 'Importar' : 'Continuar'),
            ),
          ),
          if (_currentStep > 0) ...[
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: details.onStepCancel,
                child: Text(_currentStep == 4 ? 'Cancelar' : 'Atrás'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _canContinue() {
    switch (_currentStep) {
      case 0:
        return _rows.isNotEmpty;
      case 1:
        return _hasFechaAndCliente;
      case 2:
        return true;
      case 3:
        return _preview != null && !_loadingPreview;
      case 4:
        return !_importing;
      default:
        return false;
    }
  }

  // ─── Navigation ────────────────────────────────────────

  void _onStepContinue() {
    if (_currentStep == 3) {
      _executeImport();
      setState(() => _currentStep = 4);
    } else if (_currentStep == 4) {
      return;
    } else {
      if (_currentStep == 2) {
        _loadPreview();
      }
      setState(() => _currentStep++);
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  // ─── File picking ──────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final path = file.path;
    if (path == null) return;

    setState(() {
      _fileName = file.name;
      _isCsv = file.extension?.toLowerCase() == 'csv';
      _rows = [];
      _columns = [];
      _columnRoles = {};
    });

    if (_isCsv) {
      final content = await File(path).readAsString();
      final rows = ImportService.parseCsv(content, separator: _csvSeparator);
      _applyRows(rows);
    } else {
      final bytes = await File(path).readAsBytes();
      final rows = ImportService.parseExcel(bytes);
      _applyRows(rows);
    }
  }

  void _applyRows(List<List<String>> rows) {
    final columns = ImportService.detectColumns(rows);
    final autoMapping = ImportService.autoDetectJesusFormat(rows);

    setState(() {
      _rows = rows;
      _columns = columns;
      if (autoMapping != null) {
        _columnRoles = autoMapping;
      }
    });
  }

  // ─── Preview computation ───────────────────────────────

  Future<void> _loadPreview() async {
    setState(() => _loadingPreview = true);

    final clients = ref.read(clientsProvider).valueOrNull ?? [];
    final mapping = ImportMapping(
      columnRoles: _columnRoles,
      year: _year,
      defaultStatus: _defaultStatus,
      createClients: _createClients,
    );

    final preview = await ImportService.computePreview(_rows, mapping, clients);

    if (mounted) {
      setState(() {
        _preview = preview;
        _loadingPreview = false;
      });
    }
  }

  // ─── Execute import ────────────────────────────────────

  Future<void> _executeImport() async {
    setState(() {
      _importing = true;
      _progressCurrent = 0;
      _progressTotal = 0;
      _result = null;
    });

    final clients = ref.read(clientsProvider).valueOrNull ?? [];
    final mapping = ImportMapping(
      columnRoles: _columnRoles,
      year: _year,
      defaultStatus: _defaultStatus,
      createClients: _createClients,
    );

    final result = await ImportService.executeImport(
      _rows,
      mapping,
      clients,
      onProgress: (current, total) {
        if (mounted) {
          setState(() {
            _progressCurrent = current;
            _progressTotal = total;
          });
        }
      },
    );

    // Refresh providers
    ref.invalidate(gigsProvider);
    ref.invalidate(clientsProvider);

    if (mounted) {
      setState(() {
        _importing = false;
        _result = result;
      });
    }
  }

  Future<void> _showXlsxRepairDialog() async {
    var year = DateTime.now().year;
    var loading = false;
    XlsxRepairPreview? preview;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> loadPreview() async {
              setLocalState(() => loading = true);
              final p = await ImportService.previewXlsxOfficialRepair(
                year: year,
              );
              setLocalState(() {
                preview = p;
                loading = false;
              });
            }

            Future<void> applyFix() async {
              final navigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(this.context);
              setLocalState(() => loading = true);
              final updated = await ImportService.applyXlsxOfficialRepair(
                year: year,
              );
              if (!mounted) return;
              ref.invalidate(gigsProvider);
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Reparadas $updated facturas XLSX de $year'),
                ),
              );
            }

            return AlertDialog(
              title: const Text('Reparar importación XLSX'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: year,
                    decoration: const InputDecoration(labelText: 'Año'),
                    items: List.generate(10, (i) => DateTime.now().year - i)
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: loading
                        ? null
                        : (v) => setLocalState(() {
                            year = v ?? year;
                            preview = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  if (preview != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Facturas: ${preview!.candidates}'),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Total actual: ${CurrencyFormatter.format(preview!.totalActual)}',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Total corregido: ${CurrencyFormatter.format(preview!.totalCorregido)}',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Base: ${CurrencyFormatter.format(preview!.totalBase)} · IVA: ${CurrencyFormatter.format(preview!.totalIva)}',
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cerrar'),
                ),
                TextButton(
                  onPressed: loading ? null : loadPreview,
                  child: const Text('Preview'),
                ),
                ElevatedButton(
                  onPressed:
                      loading || preview == null || preview!.candidates == 0
                      ? null
                      : applyFix,
                  child: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
