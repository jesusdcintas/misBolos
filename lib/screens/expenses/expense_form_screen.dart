import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../models/expense.dart';
import '../../providers/expenses_provider.dart';

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

  DateTime _fecha = DateTime.now();
  ExpenseCategory _categoria = ExpenseCategory.otros;
  bool _esDeducible = true;
  double _porcentajeDeduccion = 100.0;
  String? _documentoPath;
  bool _loading = false;
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _documentoPath = result.files.single.path);
    }
  }

  Future<void> _pickPhoto() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _documentoPath = picked.path);
    }
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
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDocument,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('PDF'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_outlined, size: 18),
                  label: const Text('Foto'),
                ),
              ],
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
