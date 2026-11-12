import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/expense.dart';
import '../../providers/expenses_provider.dart';
import '../../services/ai_attachment_service.dart';
import '../../core/theme/app_theme_colors.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  final int expenseId;

  const ExpenseDetailScreen({super.key, required this.expenseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenseAsync = ref.watch(expenseByIdProvider(expenseId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles del gasto o inversión'),
        actions: [
          expenseAsync.maybeWhen(
            data: (expense) => expense != null
                ? IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () =>
                        context.push('/expense/edit/${expense.id}'),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: expenseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (expense) {
          if (expense == null) {
            return const Center(child: Text('Gasto no encontrado'));
          }
          return _ExpenseDetail(expense: expense, ref: ref);
        },
      ),
    );
  }
}

class _ExpenseDetail extends StatelessWidget {
  final Expense expense;
  final WidgetRef ref;

  const _ExpenseDetail({required this.expense, required this.ref});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final dateFmt = DateFormat('d MMMM yyyy', 'es_ES');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cabecera
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.colors.accentSoftBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _categoryIcon(expense.categoria),
                        color: context.colors.accentSoft,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.concepto,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          Text(
                            expense.categoria.label,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _Row(label: 'Fecha', value: dateFmt.format(expense.fecha)),
                if (expense.proveedor != null)
                  _Row(label: 'Proveedor', value: expense.proveedor!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Importe
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _Row(
              label: 'Importe total',
              value: fmt.format(expense.total),
              bold: true,
            ),
          ),
        ),

        // Justificante
        if (expense.documentoPath != null) ...[
          const SizedBox(height: 12),
          if (_attachmentWarning(expense.documentoPath!) != null)
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.orange.shade200),
              ),
              color: Colors.orange.shade50,
              child: ListTile(
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                ),
                title: Text(_attachmentWarning(expense.documentoPath!)!),
                subtitle: const Text(
                  'Reasigna el adjunto para sincronizarlo en Drive.',
                ),
                trailing: TextButton(
                  onPressed: () => context.push('/expense/edit/${expense.id}'),
                  child: const Text('Reasignar'),
                ),
              ),
            ),
          if (_attachmentWarning(expense.documentoPath!) != null)
            const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.colors.border),
            ),
            child: ListTile(
              leading: Icon(Icons.attach_file, color: context.colors.accentSoft),
              title: Text(
                expense.attachmentDisplayName ??
                    expense.documentoPath!.split('/').last,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('Justificante adjunto'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openDocumento(context, expense.documentoPath!),
            ),
          ),
        ],

        // Notas
        if (expense.notas != null) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notas',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(expense.notas!),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Botón eliminar
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: context.colors.error),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Eliminar gasto'),
          onPressed: () => _confirmDelete(context, ref),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar gasto'),
        content: const Text('¿Seguro que quieres eliminar este gasto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && expense.id != null) {
      var deleteFromDrive = false;
      final hasDriveFile = expense.driveFileId?.trim().isNotEmpty == true;
      if (hasDriveFile) {
        if (!context.mounted) return;
        final alsoDrive = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Borrar también en Drive?'),
            content: const Text(
              'El documento se enviará a la papelera de Drive. '
              'En MisBolos el gasto se eliminará igualmente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sí, en Drive también'),
              ),
            ],
          ),
        );
        deleteFromDrive = alsoDrive == true;
      }
      await ref
          .read(expensesProvider.notifier)
          .remove(expense.id!, deleteFromDrive: deleteFromDrive);
      if (context.mounted) context.pop();
    }
  }

  void _openDocumento(BuildContext context, String path) {
    final file = File(path);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Archivo no encontrado')));
      return;
    }
    // Abrir con el visor del sistema (macOS/iOS/Android)
    // Para visualización nativa se puede integrar open_file si se añade la dep
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Archivo: $path')));
  }

  String? _attachmentWarning(String path) {
    final normalized = path.trim();
    if (AiAttachmentService.instance.isCrossDeviceAbsolutePath(normalized)) {
      return 'Este adjunto viene de otro dispositivo y no está disponible aquí.';
    }
    if (AiAttachmentService.instance.isTemporaryPath(normalized)) {
      return 'Este adjunto usa una ruta temporal y puede haberse borrado.';
    }
    if (!File(normalized).existsSync()) {
      return 'No existe el archivo local de este adjunto.';
    }
    return null;
  }

  IconData _categoryIcon(ExpenseCategory cat) {
    switch (cat) {
      case ExpenseCategory.combustible:
        return Icons.local_gas_station_outlined;
      case ExpenseCategory.transporte:
        return Icons.directions_car_outlined;
      case ExpenseCategory.equipo:
        return Icons.speaker_outlined;
      case ExpenseCategory.software:
        return Icons.computer_outlined;
      case ExpenseCategory.dietas:
        return Icons.restaurant_outlined;
      case ExpenseCategory.publicidad:
        return Icons.campaign_outlined;
      case ExpenseCategory.formacion:
        return Icons.school_outlined;
      case ExpenseCategory.otros:
        return Icons.receipt_outlined;
    }
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _Row({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.colors.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
