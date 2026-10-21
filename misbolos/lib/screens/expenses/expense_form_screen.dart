import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../models/expense.dart';
import '../../providers/expenses_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/ai_attachment_service.dart';
import '../../services/document_text_extractor.dart';
import '../../services/expense_pdf_parser.dart';

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
  final _totalController = TextEditingController();
  final _notasController = TextEditingController();

  DateTime _fecha = DateTime.now();
  ExpenseCategory _categoria = ExpenseCategory.otros;
  String? _documentoPath;
  String? _documentoNombreOriginal;
  bool _loading = false;
  bool _loaded = false;
  bool _fechaSugerida = false;
  bool _totalSugerido = false;
  bool _proveedorSugerido = false;
  bool _avisoAutorrelleno = false;
  bool _pdfSinTexto = false;

  double get _total =>
      double.tryParse(_totalController.text.replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    _conceptoController.dispose();
    _proveedorController.dispose();
    _totalController.dispose();
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
      _totalController.text = expense.total.toStringAsFixed(2);
      _notasController.text = expense.notas ?? '';
      _fecha = expense.fecha;
      _categoria = expense.categoria;
      _documentoPath = expense.documentoPath;
      _documentoNombreOriginal = expense.attachmentDisplayName;
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
    if (picked != null) {
      setState(() {
        _fecha = picked;
        _fechaSugerida = false;
      });
    }
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
        if (widget.expenseId == null) await _autorrellenarDesdePdf(path);
      }
    } catch (e) {
      _showPickerError('No se pudo seleccionar el PDF: $e');
    }
  }

  Future<void> _autorrellenarDesdePdf(String path) async {
    String? texto;
    try {
      texto = await DocumentTextExtractor.instance.tryExtractText(path);
    } catch (_) {
      texto = null;
    }
    String? nifUsuario;
    String? nombreUsuario;
    try {
      final settings = await ref.read(settingsProvider.future);
      nifUsuario = settings.emisorNIF;
      nombreUsuario = settings.emisorNombre;
    } catch (_) {}
    final result = texto == null
        ? null
        : ExpensePdfParser.parse(
            texto,
            nifUsuario: nifUsuario,
            nombreUsuario: nombreUsuario,
          );
    if (!mounted) return;

    setState(() {
      _limpiarSugerencias();
      if (result == null || !result.algunoEncontrado) {
        _pdfSinTexto = true;
        return;
      }
      _avisoAutorrelleno = true;
      final fecha = result.fecha.valor;
      if (fecha != null) {
        _fecha = fecha;
        _fechaSugerida = true;
      }
      final total = result.total.valor;
      if (total != null) {
        _totalController.text = total.toStringAsFixed(2);
        _totalSugerido = true;
      }
      final proveedor = result.proveedor.valor;
      if (proveedor != null) {
        _proveedorController.text = proveedor;
        _proveedorSugerido = true;
      }
    });
  }

  void _limpiarSugerencias() {
    _fechaSugerida = false;
    _totalSugerido = false;
    _proveedorSugerido = false;
    _avisoAutorrelleno = false;
    _pdfSinTexto = false;
  }

  void _showPickerError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final proceed = await _confirmPotentialDuplicate();
    if (!proceed) return;

    setState(() => _loading = true);

    final expense = Expense(
      id: widget.expenseId,
      fecha: _fecha,
      concepto: _conceptoController.text.trim(),
      proveedor: _proveedorController.text.trim().isEmpty
          ? null
          : _proveedorController.text.trim(),
      importeBase: _total,
      ivaRate: 0,
      ivaAmount: 0,
      total: _total,
      categoria: _categoria,
      esDeducible: false,
      porcentajeDeduccion: 0,
      documentoPath: _documentoPath,
      attachmentOriginalName: _documentoNombreOriginal,
      notas: _notasController.text.trim().isEmpty
          ? null
          : _notasController.text.trim(),
    );

    if (widget.expenseId != null) {
      await ref.read(expensesProvider.notifier).updateExpense(expense);
    } else {
      await ref.read(expensesProvider.notifier).add(expense);
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
    final repo = ref.read(expenseRepositoryProvider);
    final all = await repo.getAll();
    final targetConcept = _conceptoController.text.trim().toLowerCase();
    final targetProvider = _proveedorController.text.trim().toLowerCase();
    final targetTotal = _total;

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final duplicates = all.where((e) {
      if (widget.expenseId != null && e.id == widget.expenseId) return false;
      if (!sameDay(e.fecha, _fecha)) return false;
      final sameConcept = e.concepto.trim().toLowerCase() == targetConcept;
      final sameProvider =
          (e.proveedor ?? '').trim().toLowerCase() == targetProvider;
      final sameTotal = (e.total - targetTotal).abs() < 0.01;
      return sameConcept && sameProvider && sameTotal;
    }).toList();

    if (duplicates.isEmpty || !mounted) return true;

    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final dateFmt = DateFormat('dd/MM/yyyy');
    final preview = duplicates
        .take(3)
        .map((e) {
          final provider = e.proveedor?.isNotEmpty == true
              ? e.proveedor!
              : 'Sin proveedor';
          return '• ${dateFmt.format(e.fecha)} · ${e.concepto} · $provider · ${fmt.format(e.total)}';
        })
        .join('\n');

    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Posible gasto duplicado'),
        content: Text(
          'Se detectó ${duplicates.length == 1 ? '1 gasto igual' : '${duplicates.length} gastos iguales'}.\n\n$preview\n\n¿Quieres guardarlo igualmente?',
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
            if (_avisoAutorrelleno) ...[
              const _AvisoPdf(
                icon: Icons.fact_check_outlined,
                color: AppColors.warning,
                background: AppColors.warningBg,
                texto:
                    'Los datos se han leído automáticamente del PDF. Comprueba '
                    'la fecha, el total y el proveedor antes de guardar.',
              ),
              const SizedBox(height: 12),
            ],

            // Fecha
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.calendar_today_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Fecha'),
              subtitle: Text(dateFmt.format(_fecha)),
              trailing: _fechaSugerida ? const _EtiquetaSugerido() : null,
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
              decoration: InputDecoration(
                labelText: 'Proveedor',
                hintText: 'Ej: Amazon, Repsol',
                helper: _proveedorSugerido
                    ? const _EtiquetaSugerido()
                    : null,
              ),
              onChanged: (_) {
                if (_proveedorSugerido) {
                  setState(() => _proveedorSugerido = false);
                }
              },
            ),
            const SizedBox(height: 16),

            // Importe total
            TextFormField(
              controller: _totalController,
              decoration: InputDecoration(
                labelText: 'Importe total *',
                suffixText: '€',
                helper: _totalSugerido ? const _EtiquetaSugerido() : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() => _totalSugerido = false),
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
            const SizedBox(height: 16),

            // Categoría
            DropdownButtonFormField<ExpenseCategory>(
              initialValue: _categoria,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: ExpenseCategory.values
                  .map(
                    (cat) =>
                        DropdownMenuItem(value: cat, child: Text(cat.label)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _categoria = v);
              },
            ),
            const SizedBox(height: 16),

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
                  (_documentoNombreOriginal?.trim().isNotEmpty == true
                      ? _documentoNombreOriginal!
                      : _documentoPath!.split('/').last),
                  overflow: TextOverflow.ellipsis,
                ),
                onDeleted: () => setState(() {
                  _documentoPath = null;
                  _documentoNombreOriginal = null;
                  _limpiarSugerencias();
                }),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _pickDocument,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Seleccionar PDF'),
            ),
            if (_pdfSinTexto) ...[
              const SizedBox(height: 8),
              const _AvisoPdf(
                icon: Icons.info_outline,
                color: AppColors.textSecondary,
                background: AppColors.primaryLight,
                texto:
                    'Este PDF no tiene texto legible. Introduce los datos '
                    'manualmente.',
              ),
            ],
            if (widget.expenseId == null) ...[
              const SizedBox(height: 8),
              const _AvisoPdf(
                icon: Icons.phone_iphone,
                color: AppColors.textSecondary,
                background: AppColors.primaryLight,
                texto:
                    '¿Tienes una foto del ticket? En iPhone puedes convertirla '
                    'a PDF: Compartir → Imprimir → Guardar como PDF, o usa '
                    'Escanear documentos en la app Notas.',
              ),
            ],
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

class _EtiquetaSugerido extends StatelessWidget {
  const _EtiquetaSugerido();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_fix_high, size: 12, color: AppColors.warning),
          SizedBox(width: 4),
          Text(
            'Sugerido',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvisoPdf extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String texto;

  const _AvisoPdf({
    required this.icon,
    required this.color,
    required this.background,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
