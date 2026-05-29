import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../models/asset.dart';
import '../../models/investment_extraction_result.dart';
import '../../providers/assets_provider.dart';
import '../../services/ai_attachment_service.dart';
import '../../services/document_text_extractor.dart';
import '../../services/investment_ai_extractor.dart';

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
  final _iaTextController = TextEditingController();

  DateTime _fechaCompra = DateTime.now();
  AssetCategory _categoria = AssetCategory.otros;
  double _ivaRate = 21.0;
  String? _documentoPath;
  String? _documentoNombreOriginal;
  bool _loading = false;
  bool _extracting = false;
  bool _loaded = false;

  // Getters para el preview en tiempo real
  double get _importeConIva =>
      double.tryParse(_importeTotalController.text.replaceAll(',', '.')) ?? 0;
  double get _baseImponible =>
      _ivaRate > 0 ? _importeConIva / (1 + _ivaRate / 100) : _importeConIva;
  double get _ivaAmount => _importeConIva - _baseImponible;
  double get _valorResidual =>
      double.tryParse(_valorResidualController.text.replaceAll(',', '.')) ?? 0;
  int get _vidaUtilAnos => int.tryParse(_vidaUtilController.text) ?? 0;

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
    _iaTextController.dispose();
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
    final asset = await ref
        .read(assetRepositoryProvider)
        .getById(widget.assetId!);
    if (asset == null || !mounted) return;
    setState(() {
      _descripcionController.text = asset.descripcion;
      _importeTotalController.text =
          (asset.importeConIva > 0 ? asset.importeConIva : asset.importeTotal)
              .toStringAsFixed(2);
      _ivaRate = asset.ivaRate;
      _valorResidualController.text = asset.valorResidual.toStringAsFixed(2);
      _vidaUtilController.text = asset.vidaUtilAnos.toString();
      _notasController.text = asset.notas ?? '';
      _fechaCompra = asset.fechaCompra;
      _categoria = asset.categoria;
      _documentoPath = asset.documentoPath;
      _documentoNombreOriginal = asset.attachmentDisplayName;
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
    try {
      final path = await AiAttachmentService.instance.pickPdf();
      if (path != null && mounted) {
        setState(() {
          _documentoPath = path;
          _documentoNombreOriginal = AiAttachmentService.instance
              .normalizeOriginalFileName(path);
        });
      }
    } catch (e) {
      _showPickerError('No se pudo seleccionar el PDF: $e');
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final path = await AiAttachmentService.instance.pickImageFromGallery();
      if (path != null && mounted) {
        setState(() {
          _documentoPath = path;
          _documentoNombreOriginal = AiAttachmentService.instance
              .normalizeOriginalFileName(path);
        });
      }
    } catch (e) {
      _showPickerError('No se pudo seleccionar la imagen: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final path = await AiAttachmentService.instance.takePhotoWithCamera();
      if (path != null && mounted) {
        setState(() {
          _documentoPath = path;
          _documentoNombreOriginal = AiAttachmentService.instance
              .normalizeOriginalFileName(path);
        });
      }
    } catch (e) {
      _showPickerError('No se pudo abrir la cámara: $e');
    }
  }

  void _showPickerError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _extractWithAi() async {
    var inputText = _iaTextController.text.trim();
    if (_extracting || _loading) return;

    setState(() => _extracting = true);
    try {
      final path = _documentoPath;
      if (path != null && AiAttachmentService.instance.isImagePath(path)) {
        final result = await InvestmentAiExtractor.instance
            .extractFromImagePath(path);
        if (!mounted) return;
        await _confirmApplyExtraction(result);
        return;
      }

      if (inputText.isEmpty && path != null) {
        final extracted = await DocumentTextExtractor.instance.tryExtractText(
          path,
        );
        if (extracted != null && extracted.trim().isNotEmpty) {
          inputText = extracted.trim();
          if (mounted) setState(() => _iaTextController.text = inputText);
        }
      }

      if (inputText.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adjunta una factura o escribe una descripción.'),
          ),
        );
        return;
      }

      final result = path == null
          ? await InvestmentAiExtractor.instance.extractFromText(inputText)
          : await InvestmentAiExtractor.instance.extractFromReceiptText(
              inputText,
            );
      if (!mounted) return;
      await _confirmApplyExtraction(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo extraer la inversión: $e')),
      );
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _confirmApplyExtraction(
    InvestmentExtractionResult result,
  ) async {
    final moneyFmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final dateFmt = DateFormat('dd/MM/yyyy');
    final summary = <String>[
      if (result.name != null) 'Nombre inversión: ${result.name}',
      if (result.supplier != null) 'Proveedor: ${result.supplier}',
      if (result.invoiceNumber != null) 'Nº factura: ${result.invoiceNumber}',
      if (result.purchaseDate != null)
        'Fecha compra: ${dateFmt.format(result.purchaseDate!)}',
      if (result.concept != null) 'Concepto: ${result.concept}',
      if (result.category != null) 'Categoría: ${result.category!.label}',
      if (result.baseAmount != null)
        'Base amortizable: ${moneyFmt.format(result.baseAmount)}',
      if (result.taxAmount != null)
        'IVA soportado: ${moneyFmt.format(result.taxAmount)}',
      if (result.vatRate != null)
        'IVA %: ${result.vatRate!.toStringAsFixed(0)}%',
      if (result.totalAmount != null)
        'Total factura: ${moneyFmt.format(result.totalAmount)}',
      if (result.usefulLifeYears != null)
        'Vida útil sugerida: ${result.usefulLifeYears} años',
      if (result.maxAnnualPercentage != null)
        'Porcentaje máximo anual: ${result.maxAnnualPercentage!.toStringAsFixed(0)}%',
      if (result.annualAmortizationAmount != null)
        'Amortización anual estimada: ${moneyFmt.format(result.annualAmortizationAmount)}',
      if (result.deductiblePercentage != null)
        'Porcentaje deducible: ${result.deductiblePercentage!.toStringAsFixed(0)}%',
      'Confianza estimada: ${(result.confidence * 100).clamp(0, 100).toStringAsFixed(0)}%',
    ];

    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Datos detectados'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in summary) Text(line),
              if (result.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Revisa estos puntos:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                for (final warning in result.warnings) Text('• $warning'),
              ],
              if (result.confidence < 0.75) ...[
                const SizedBox(height: 12),
                const Text(
                  'Confianza baja: revisa manualmente antes de guardar.',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Corregir manualmente'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Guardar inversión'),
          ),
        ],
      ),
    );

    if (apply != true || !mounted) return;

    setState(() {
      final description = result.name ?? result.concept;
      if (description != null) _descripcionController.text = description;
      if (result.purchaseDate != null) _fechaCompra = result.purchaseDate!;
      if (result.category != null) _categoria = result.category!;
      if (result.totalAmount != null) {
        _importeTotalController.text = result.totalAmount!.toStringAsFixed(2);
      } else if (result.baseAmount != null && result.taxAmount != null) {
        _importeTotalController.text = (result.baseAmount! + result.taxAmount!)
            .toStringAsFixed(2);
      }
      if (result.vatRate != null) _ivaRate = result.vatRate!;
      if (result.usefulLifeYears != null && result.usefulLifeYears! > 0) {
        _vidaUtilController.text = result.usefulLifeYears.toString();
      }
      _notasController.text = _mergeNotes(result);
    });
  }

  String _mergeNotes(InvestmentExtractionResult result) {
    final parts = <String>[
      if (_notasController.text.trim().isNotEmpty) _notasController.text.trim(),
      if (result.supplier != null) 'Proveedor: ${result.supplier}',
      if (result.invoiceNumber != null) 'Factura: ${result.invoiceNumber}',
      if (result.maxAnnualPercentage != null)
        'Máx. anual: ${result.maxAnnualPercentage!.toStringAsFixed(0)}%',
      if (result.annualAmortizationAmount != null)
        'Amortización anual IA: ${result.annualAmortizationAmount!.toStringAsFixed(2)} €',
      if (result.deductiblePercentage != null)
        'Deducible: ${result.deductiblePercentage!.toStringAsFixed(0)}%',
    ];
    return parts.join(' | ');
  }

  /// Al cambiar categoría, sugerir vida útil según Hacienda (editable)
  void _onCategoriaChanged(AssetCategory? cat) {
    if (cat == null) return;
    setState(() {
      _categoria = cat;
      if (_vidaUtilController.text.isEmpty || _vidaUtilController.text == '0') {
        final suggested = cat.vidaUtilSugerida;
        _vidaUtilController.text = suggested > 0 ? suggested.toString() : '';
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final proceed = await _confirmPotentialDuplicate();
    if (!proceed) return;

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
      attachmentOriginalName: _documentoNombreOriginal,
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

    if (mounted) {
      if (_documentoPath?.trim().isNotEmpty == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Guardado localmente. Pendiente de subir a Drive.'),
          ),
        );
      }
      context.pop();
    }
  }

  Future<bool> _confirmPotentialDuplicate() async {
    final repo = ref.read(assetRepositoryProvider);
    final all = await repo.getAll();
    final targetDesc = _descripcionController.text.trim().toLowerCase();
    final targetTotal = _importeConIva > 0 ? _importeConIva : _baseImponible;

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final duplicates = all.where((a) {
      if (widget.assetId != null && a.id == widget.assetId) return false;
      if (!sameDay(a.fechaCompra, _fechaCompra)) return false;
      final sameDesc = a.descripcion.trim().toLowerCase() == targetDesc;
      final existingTotal = a.importeConIva > 0
          ? a.importeConIva
          : a.importeTotal;
      final sameTotal = (existingTotal - targetTotal).abs() < 0.01;
      return sameDesc && sameTotal;
    }).toList();

    if (duplicates.isEmpty || !mounted) return true;

    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final dateFmt = DateFormat('dd/MM/yyyy');
    final preview = duplicates
        .take(3)
        .map((a) {
          final amount = a.importeConIva > 0 ? a.importeConIva : a.importeTotal;
          return '• ${dateFmt.format(a.fechaCompra)} · ${a.descripcion} · ${fmt.format(amount)}';
        })
        .join('\n');

    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Posible inversión duplicada'),
        content: Text(
          'Se detectó ${duplicates.length == 1 ? '1 inversión igual' : '${duplicates.length} inversiones iguales'}.\n\n$preview\n\n¿Quieres guardarla igualmente?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Revisar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar igualmente'),
          ),
        ],
      ),
    );
    return keep == true;
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
                  .map(
                    (cat) => DropdownMenuItem(
                      value: cat,
                      child: Row(
                        children: [
                          Icon(
                            cat.icono,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(cat.label),
                          const SizedBox(width: 4),
                          Text(
                            '(${(cat.coeficienteMaxHacienda * 100).toStringAsFixed(0)}% máx.)',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _onCategoriaChanged,
            ),
            const SizedBox(height: 16),

            // Fecha de compra
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.calendar_today_outlined,
                color: AppColors.primary,
              ),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
                DropdownMenuItem(
                  value: 4.0,
                  child: Text('4%   — Superreducido'),
                ),
                DropdownMenuItem(value: 0.0, child: Text('0%   — Exento')),
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
                        locale: 'es_ES',
                        symbol: '€',
                      ).format(_baseImponible),
                      bold: true,
                    ),
                    _PreviewRow(
                      label: 'IVA deducible este trimestre',
                      value: NumberFormat.currency(
                        locale: 'es_ES',
                        symbol: '€',
                      ).format(_ivaAmount),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'El IVA se deduce como gasto en el trimestre de compra',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Vida útil
            TextFormField(
              controller: _vidaUtilController,
              decoration: InputDecoration(
                labelText: 'Vida útil (años) *',
                hintText: _categoria.vidaUtilSugerida > 0
                    ? 'Sugerido Hacienda: ${_categoria.vidaUtilSugerida}'
                    : 'Revisar manualmente',
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
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PreviewRow(
                      label: 'Base amortizable',
                      value: moneyFmt.format(_baseImponible),
                    ),
                    _PreviewRow(
                      label: 'Cuota mensual',
                      value: moneyFmt.format(_cuotaMensual),
                    ),
                    _PreviewRow(
                      label: 'Cuota trimestral',
                      value: moneyFmt.format(_cuotaTrimestral),
                    ),
                    _PreviewRow(
                      label: 'Cuota anual',
                      value: moneyFmt.format(_cuotaAnual),
                      bold: true,
                    ),
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
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.savings_outlined,
                        size: 18,
                        color: AppColors.success,
                      ),
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
                                color: AppColors.success,
                              ),
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
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            if (_documentoPath != null)
              Chip(
                avatar: const Icon(Icons.attach_file, size: 16),
                label: Text(
                  (_documentoNombreOriginal?.trim().isNotEmpty == true
                      ? _documentoNombreOriginal!
                      : _documentoPath!.split('/').last),
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: () => setState(() {
                  _documentoPath = null;
                  _documentoNombreOriginal = null;
                }),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDocument,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_outlined, size: 18),
                  label: const Text('Galería'),
                ),
                OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Cámara'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _extracting || _loading ? null : _extractWithAi,
              icon: _extracting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Extraer información con IA'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _iaTextController,
              decoration: const InputDecoration(
                labelText: 'Texto detectado de la factura o descripción manual',
                hintText:
                    'Puedes pegar aquí el texto de una factura o escribir una descripción como: Portátil 1.200€, IVA 21%, comprado el 04/03/2026.',
              ),
              minLines: 3,
              maxLines: 6,
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
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: bold ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
