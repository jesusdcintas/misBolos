import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../models/expense.dart';
import '../../models/expense_extraction_result.dart';
import '../../providers/expenses_provider.dart';
import '../../services/ai_attachment_service.dart';
import '../../services/document_text_extractor.dart';
import '../../services/expense_ai_extractor.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  final int? expenseId;

  const ExpenseFormScreen({super.key, this.expenseId});

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _conceptoController = TextEditingController();
  final _proveedorController = TextEditingController();
  final _importeBaseController = TextEditingController();
  final _ivaRateController = TextEditingController(text: '21');
  final _notasController = TextEditingController();
  final _iaTextController = TextEditingController();

  DateTime _fecha = DateTime.now();
  ExpenseCategory _categoria = ExpenseCategory.otros;
  bool _esDeducible = true;
  double _porcentajeDeduccion = 100.0;
  String? _documentoPath;
  bool _loading = false;
  bool _extracting = false;
  bool _loaded = false;

  double get _importeBase =>
      double.tryParse(_importeBaseController.text.replaceAll(',', '.')) ?? 0;
  double get _ivaRate =>
      double.tryParse(_ivaRateController.text.replaceAll(',', '.')) ?? 21.0;
  double get _ivaAmount => _importeBase * (_ivaRate / 100);
  double get _total => _importeBase + _ivaAmount;

  @override
  void dispose() {
    _conceptoController.dispose();
    _proveedorController.dispose();
    _importeBaseController.dispose();
    _ivaRateController.dispose();
    _notasController.dispose();
    _iaTextController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded && widget.expenseId != null) {
      _loadExpense();
    }
  }

  Future<void> _loadExpense() async {
    final expense = await ref
        .read(expenseRepositoryProvider)
        .getById(widget.expenseId!);
    if (expense == null || !mounted) return;
    setState(() {
      _conceptoController.text = expense.concepto;
      _proveedorController.text = expense.proveedor ?? '';
      _importeBaseController.text =
          expense.importeBase.toStringAsFixed(2);
      _ivaRateController.text = expense.ivaRate.toStringAsFixed(0);
      _notasController.text = expense.notas ?? '';
      _fecha = expense.fecha;
      _categoria = expense.categoria;
      _esDeducible = expense.esDeducible;
      _porcentajeDeduccion = expense.porcentajeDeduccion;
      _documentoPath = expense.documentoPath;
      _loaded = true;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _pickDocument() async {
    try {
      final path = await AiAttachmentService.instance.pickPdf();
      if (path != null && mounted) setState(() => _documentoPath = path);
    } catch (e) {
      _showPickerError('No se pudo seleccionar el PDF: $e');
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final path = await AiAttachmentService.instance.pickImageFromGallery();
      if (path != null && mounted) setState(() => _documentoPath = path);
    } catch (e) {
      _showPickerError('No se pudo seleccionar la imagen: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final path = await AiAttachmentService.instance.takePhotoWithCamera();
      if (path != null && mounted) setState(() => _documentoPath = path);
    } catch (e) {
      _showPickerError('No se pudo abrir la cámara: $e');
    }
  }

  void _showPickerError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final expense = Expense(
      id: widget.expenseId,
      fecha: _fecha,
      concepto: _conceptoController.text.trim(),
      proveedor: _proveedorController.text.trim().isEmpty
          ? null
          : _proveedorController.text.trim(),
      importeBase: _importeBase,
      ivaRate: _ivaRate,
      ivaAmount: _ivaAmount,
      total: _total,
      categoria: _categoria,
      esDeducible: _esDeducible,
      porcentajeDeduccion: _porcentajeDeduccion,
      documentoPath: _documentoPath,
      notas: _notasController.text.trim().isEmpty
          ? null
          : _notasController.text.trim(),
    );

    if (widget.expenseId != null) {
      await ref.read(expensesProvider.notifier).updateExpense(expense);
    } else {
      await ref.read(expensesProvider.notifier).add(expense);
    }

    if (mounted) context.pop();
  }

  Future<void> _extractWithAi() async {
    var inputText = _iaTextController.text.trim();
    if (_extracting || _loading) return;

    setState(() => _extracting = true);
    try {
      final documentPath = _documentoPath;
      final hasImage = documentPath != null &&
          AiAttachmentService.instance.isImagePath(documentPath);

      if (hasImage) {
        final result = await ExpenseAiExtractor.instance
            .extractExpenseFromImagePath(documentPath);
        if (!mounted) return;
        await _confirmApplyExtraction(result);
        return;
      }

      if (inputText.isEmpty && documentPath != null) {
        final extracted = await DocumentTextExtractor.instance
            .tryExtractText(documentPath);
        if (extracted != null && extracted.trim().isNotEmpty) {
          inputText = extracted.trim();
          if (mounted) {
            setState(() => _iaTextController.text = inputText);
          }
        }
      }

      if (inputText.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pude leer texto automáticamente. Pega OCR o texto manual.',
            ),
          ),
        );
        return;
      }

      final result = _documentoPath == null
          ? await ExpenseAiExtractor.instance.extractExpenseFromText(inputText)
          : await ExpenseAiExtractor.instance.extractExpenseFromReceiptText(
              prompt:
                  'Extrae un gasto desde OCR de ticket/factura. No inventes campos.',
              receiptText: inputText,
            );
      if (!mounted) return;
      await _confirmApplyExtraction(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo extraer automáticamente: $e')),
      );
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _confirmApplyExtraction(ExpenseExtractionResult result) async {
    final summary = <String>[
      if (result.concepto != null) 'Concepto: ${result.concepto}',
      if (result.proveedor != null) 'Proveedor fiscal: ${result.proveedor}',
      if (result.estacion != null) 'Estación: ${result.estacion}',
      if (result.numeroFactura != null) 'Factura: ${result.numeroFactura}',
      if (result.fecha != null) 'Fecha: ${DateFormat('dd/MM/yyyy').format(result.fecha!)}',
      if (result.fechaOperacion != null)
        'F. Operación: ${DateFormat('dd/MM/yyyy').format(result.fechaOperacion!)}',
      if (result.matriculaVehiculo != null)
        'Matrícula: ${result.matriculaVehiculo}',
      if (result.litros != null) 'Litros: ${result.litros!.toStringAsFixed(2)}',
      if (result.precioPorLitro != null)
        'Precio/L: ${result.precioPorLitro!.toStringAsFixed(3)} €',
      if (result.importeBase != null)
        'Base: ${result.importeBase!.toStringAsFixed(2)} €',
      if (result.ivaRate != null) 'IVA: ${result.ivaRate!.toStringAsFixed(0)}%',
      if (result.importeIva != null)
        'IVA importe: ${result.importeIva!.toStringAsFixed(2)} €',
      if (result.importeTotal != null)
        'Total: ${result.importeTotal!.toStringAsFixed(2)} €',
      if (result.descuento != null)
        'Descuento: ${result.descuento!.toStringAsFixed(2)} €',
      if (result.esDeducible != null)
        'Deducible: ${result.esDeducible! ? 'Sí' : 'No'}',
      if (result.porcentajeDeduccion != null)
        'Deducción: ${result.porcentajeDeduccion!.toStringAsFixed(0)}%',
      if (result.categoria != null) 'Categoría: ${result.categoria!.label}',
      if (result.confidence > 0)
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
              if (summary.isEmpty)
                const Text('No se detectaron campos suficientes.'),
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
            child: const Text('Guardar gasto'),
          ),
        ],
      ),
    );

    if (apply != true || !mounted) return;

    setState(() {
      if (result.concepto != null) _conceptoController.text = result.concepto!;
      if (result.proveedor != null) {
        _proveedorController.text = result.proveedor!;
      }
      if (result.fecha != null) _fecha = result.fecha!;
      if (result.importeBase != null) {
        _importeBaseController.text = result.importeBase!.toStringAsFixed(2);
      }
      if (result.ivaRate != null) {
        _ivaRateController.text = result.ivaRate!.toStringAsFixed(0);
      }
      if (result.categoria != null) _categoria = result.categoria!;
      if (result.esDeducible != null) _esDeducible = result.esDeducible!;
      if (result.porcentajeDeduccion != null) {
        _porcentajeDeduccion = result.porcentajeDeduccion!.clamp(0, 100);
      }
      if (result.notas != null && result.notas!.isNotEmpty) {
        _notasController.text = result.notas!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMMM yyyy', 'es_ES');
    final isEditing = widget.expenseId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar gasto' : 'Nuevo gasto'),
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
            // Fecha
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined,
                  color: AppColors.primary),
              title: const Text('Fecha'),
              subtitle: Text(dateFmt.format(_fecha)),
              onTap: _pickDate,
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Concepto
            TextFormField(
              controller: _conceptoController,
              decoration: const InputDecoration(
                labelText: 'Concepto *',
                hintText: 'Ej: Cables XLR, Gasolina Madrid',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null,
            ),
            const SizedBox(height: 12),

            // Proveedor
            TextFormField(
              controller: _proveedorController,
              decoration: const InputDecoration(
                labelText: 'Proveedor',
                hintText: 'Ej: Amazon, Repsol',
              ),
            ),
            const SizedBox(height: 16),

            // Importe base + IVA
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _importeBaseController,
                    decoration: const InputDecoration(
                      labelText: 'Base imponible *',
                      suffixText: '€',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Obligatorio';
                      }
                      if (double.tryParse(v.replaceAll(',', '.')) == null) {
                        return 'Número no válido';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _ivaRateController,
                    decoration: const InputDecoration(
                      labelText: 'IVA %',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_importeBase > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'IVA: ${_ivaAmount.toStringAsFixed(2)} €   Total: ${_total.toStringAsFixed(2)} €',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Categoría
            DropdownButtonFormField<ExpenseCategory>(
              initialValue: _categoria,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: ExpenseCategory.values
                  .map((cat) => DropdownMenuItem(
                        value: cat,
                        child: Text(cat.label),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _categoria = v);
              },
            ),
            const SizedBox(height: 16),

            // Deducibilidad
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gasto deducible'),
              value: _esDeducible,
              onChanged: (v) => setState(() => _esDeducible = v),
            ),
            if (_esDeducible) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('% Deducción:',
                      style: TextStyle(color: AppColors.textSecondary)),
                  Expanded(
                    child: Slider(
                      value: _porcentajeDeduccion,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '${_porcentajeDeduccion.toStringAsFixed(0)} %',
                      onChanged: (v) =>
                          setState(() => _porcentajeDeduccion = v),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${_porcentajeDeduccion.toStringAsFixed(0)} %',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // Justificante
            const Text(
              'Justificante',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
                OutlinedButton.icon(
                  onPressed: _extracting || _loading ? null : _extractWithAi,
                  icon: _extracting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Extraer IA'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _iaTextController,
              decoration: const InputDecoration(
                labelText: 'Texto para analizar con IA',
                hintText:
                    'Puedes pegar aquí el texto de una factura, ticket o escribir una descripción como: Gasolina Repsol 29,48€, fecha 04/03/2026, IVA 21%.',
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
