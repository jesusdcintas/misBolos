import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../models/asset.dart';
import '../../providers/assets_provider.dart';

class AssetFormScreen extends ConsumerStatefulWidget {
  final int? assetId;

  const AssetFormScreen({super.key, this.assetId});

  @override
  ConsumerState<AssetFormScreen> createState() => _AssetFormScreenState();
}

class _AssetFormScreenState extends ConsumerState<AssetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  final _importeTotalController = TextEditingController();
  final _valorResidualController = TextEditingController(text: '0');
  final _vidaUtilController = TextEditingController();
  final _notasController = TextEditingController();

  DateTime _fechaCompra = DateTime.now();
  AssetCategory _categoria = AssetCategory.otros;
  double _ivaRate = 21.0;
  String? _documentoPath;
  bool _loading = false;
  bool _loaded = false;

  // Getters para el preview en tiempo real
  double get _importeConIva =>
      double.tryParse(_importeTotalController.text.replaceAll(',', '.')) ?? 0;
  double get _baseImponible =>
      _ivaRate > 0 ? _importeConIva / (1 + _ivaRate / 100) : _importeConIva;
  double get _ivaAmount => _importeConIva - _baseImponible;
  double get _valorResidual =>
      double.tryParse(_valorResidualController.text.replaceAll(',', '.')) ?? 0;
  int get _vidaUtilAnos =>
      int.tryParse(_vidaUtilController.text) ?? 0;

  double get _cuotaAnual =>
      _vidaUtilAnos > 0 ? (_baseImponible - _valorResidual) / _vidaUtilAnos : 0;
  double get _cuotaTrimestral => _cuotaAnual / 4;
  double get _cuotaMensual => _cuotaAnual / 12;

  @override
  void dispose() {
    _descripcionController.dispose();
    _importeTotalController.dispose();
    _valorResidualController.dispose();
    _vidaUtilController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded && widget.assetId != null) {
      _loadAsset();
    }
  }

  Future<void> _loadAsset() async {
    final asset =
        await ref.read(assetRepositoryProvider).getById(widget.assetId!);
    if (asset == null || !mounted) return;
    setState(() {
      _descripcionController.text = asset.descripcion;
      _importeTotalController.text =
          (asset.importeConIva > 0 ? asset.importeConIva : asset.importeTotal)
              .toStringAsFixed(2);
      _ivaRate = asset.ivaRate;
      _valorResidualController.text =
          asset.valorResidual.toStringAsFixed(2);
      _vidaUtilController.text = asset.vidaUtilAnos.toString();
      _notasController.text = asset.notas ?? '';
      _fechaCompra = asset.fechaCompra;
      _categoria = asset.categoria;
      _documentoPath = asset.documentoPath;
      _loaded = true;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaCompra,
      firstDate: DateTime(2000),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _fechaCompra = picked);
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _documentoPath = result.files.single.path);
    }
  }

  /// Al cambiar categoría, sugerir vida útil según Hacienda (editable)
  void _onCategoriaChanged(AssetCategory? cat) {
    if (cat == null) return;
    setState(() {
      _categoria = cat;
      if (_vidaUtilController.text.isEmpty ||
          _vidaUtilController.text == '0') {
        _vidaUtilController.text = cat.vidaUtilSugerida.toString();
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final asset = Asset(
      id: widget.assetId,
      descripcion: _descripcionController.text.trim(),
      fechaCompra: _fechaCompra,
      importeTotal: _baseImponible,
      importeConIva: _importeConIva,
      ivaRate: _ivaRate,
      ivaAmount: _ivaAmount,
      valorResidual: _valorResidual,
      vidaUtilAnos: _vidaUtilAnos,
      categoria: _categoria,
      documentoPath: _documentoPath,
      notas: _notasController.text.trim().isEmpty
          ? null
          : _notasController.text.trim(),
      createdAt: DateTime.now(),
    );

    if (widget.assetId != null) {
      await ref.read(assetsProvider.notifier).updateAsset(asset);
    } else {
      await ref.read(assetsProvider.notifier).add(asset);
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMMM yyyy', 'es_ES');
    final moneyFmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final isEditing = widget.assetId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar inversión' : 'Nueva inversión'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Descripción
            TextFormField(
              controller: _descripcionController,
              decoration: const InputDecoration(
                labelText: 'Descripción *',
                hintText: 'Ej: Mesa de mezclas Pioneer DDJ-1000',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null,
            ),
            const SizedBox(height: 16),

            // Categoría
            DropdownButtonFormField<AssetCategory>(
              initialValue: _categoria,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: AssetCategory.values
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Row(
                          children: [
                            Icon(cat.icono,
                                size: 18,
                                color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(cat.label),
                            const SizedBox(width: 4),
                            Text(
                              '(${(cat.coeficienteMaxHacienda * 100).toStringAsFixed(0)}% máx.)',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: _onCategoriaChanged,
            ),
            const SizedBox(height: 16),

            // Fecha de compra
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined,
                  color: AppColors.primary),
              title: const Text('Fecha de compra'),
              subtitle: Text(dateFmt.format(_fechaCompra)),
              onTap: _pickDate,
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Importe total (con IVA)
            TextFormField(
              controller: _importeTotalController,
              decoration: const InputDecoration(
                labelText: 'Importe total (con IVA) *',
                suffixText: '€',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = double.tryParse(v?.replaceAll(',', '.') ?? '');
                if (n == null || n <= 0) {
                  return 'Introduce un importe válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // IVA %
            DropdownButtonFormField<double>(
              initialValue: _ivaRate,
              decoration: const InputDecoration(labelText: 'IVA %'),
              items: const [
                DropdownMenuItem(value: 21.0, child: Text('21%  — General')),
                DropdownMenuItem(value: 10.0, child: Text('10%  — Reducido')),
                DropdownMenuItem(value: 4.0,  child: Text('4%   — Superreducido')),
                DropdownMenuItem(value: 0.0,  child: Text('0%   — Exento')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _ivaRate = v);
              },
            ),
            const SizedBox(height: 12),

            // Card: base imponible + IVA deducible (solo lectura)
            if (_importeConIva > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PreviewRow(
                      label: 'Base imponible (amortizable)',
                      value: NumberFormat.currency(
                              locale: 'es_ES', symbol: '€')
                          .format(_baseImponible),
                      bold: true,
                    ),
                    _PreviewRow(
                      label: 'IVA deducible este trimestre',
                      value: NumberFormat.currency(
                              locale: 'es_ES', symbol: '€')
                          .format(_ivaAmount),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'El IVA se deduce como gasto en el trimestre de compra',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Valor residual
            TextFormField(
              controller: _valorResidualController,
              decoration: const InputDecoration(
                labelText: 'Valor residual',
                hintText: '0',
                suffixText: '€',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Vida útil
            TextFormField(
              controller: _vidaUtilController,
              decoration: InputDecoration(
                labelText: 'Vida útil (años) *',
                hintText:
                    'Sugerido Hacienda: ${_categoria.vidaUtilSugerida}',
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Introduce años válidos';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Preview cuotas
            if (_importeConIva > 0 && _vidaUtilAnos > 0) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preview amortización lineal',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _PreviewRow(
                        label: 'Base amortizable',
                        value: moneyFmt.format(_baseImponible)),
                    _PreviewRow(
                        label: 'Cuota mensual',
                        value: moneyFmt.format(_cuotaMensual)),
                    _PreviewRow(
                        label: 'Cuota trimestral',
                        value: moneyFmt.format(_cuotaTrimestral)),
                    _PreviewRow(
                        label: 'Cuota anual',
                        value: moneyFmt.format(_cuotaAnual),
                        bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_ivaRate > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.savings_outlined,
                          size: 18, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'IVA deducible este trimestre: ${moneyFmt.format(_ivaAmount)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Se deduce como gasto en el trimestre de la compra, no se amortiza',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.success),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 16),

            // Justificante
            const Text(
              'Justificante (factura de compra)',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (_documentoPath != null)
              Chip(
                avatar: const Icon(Icons.attach_file, size: 16),
                label: Text(
                  _documentoPath!.split('/').last,
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: () => setState(() => _documentoPath = null),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _pickDocument,
              icon: const Icon(Icons.attach_file_outlined, size: 18),
              label: const Text('Adjuntar factura'),
            ),
            const SizedBox(height: 16),

            // Notas
            TextFormField(
              controller: _notasController,
              decoration: const InputDecoration(
                labelText: 'Notas',
                hintText: 'Observaciones opcionales',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _PreviewRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal,
                  color:
                      bold ? AppColors.primary : AppColors.textPrimary)),
        ],
      ),
    );
  }
}
