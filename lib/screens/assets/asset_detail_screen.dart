import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../models/asset.dart';
import '../../providers/assets_provider.dart';

class AssetDetailScreen extends ConsumerWidget {
  final int assetId;

  const AssetDetailScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetAsync = ref.watch(assetByIdProvider(assetId));

    return assetAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (asset) {
        if (asset == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Inversión no encontrada')),
          );
        }
        return _AssetDetailContent(asset: asset, ref: ref, context: context);
      },
    );
  }
}

class _AssetDetailContent extends StatelessWidget {
  final Asset asset;
  final WidgetRef ref;
  final BuildContext context;

  const _AssetDetailContent({
    required this.asset,
    required this.ref,
    required this.context,
  });

  @override
  Widget build(BuildContext buildContext) {
    final dateFmt = DateFormat('d MMM yyyy', 'es_ES');
    final moneyFmt = NumberFormat.currency(locale: 'es_ES', symbol: '€');
    final pct = asset.importeTotal > 0
        ? (asset.amortizacionAcumulada / asset.importeTotal).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(asset.descripcion),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => buildContext.push('/asset/edit/${asset.id}'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Encabezado
          Card(
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
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(asset.categoria.icono,
                            size: 24, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              asset.descripcion,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              asset.categoria.label,
                              style: const TextStyle(
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (!asset.activo)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Dado de baja',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  _InfoRow(
                    label: 'Fecha de compra',
                    value: dateFmt.format(asset.fechaCompra),
                  ),
                  _InfoRow(
                    label: 'Importe total',
                    value: moneyFmt.format(asset.importeTotal),
                  ),
                  _InfoRow(
                    label: 'Valor residual',
                    value: moneyFmt.format(asset.valorResidual),
                  ),
                  _InfoRow(
                    label: 'Vida útil',
                    value: '${asset.vidaUtilAnos} años',
                  ),
                  _InfoRow(
                    label: 'Método',
                    value: asset.metodoAmortizacion,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Situación actual
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Situación actual',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ValueBox(
                          label: 'Valor contable',
                          value: moneyFmt.format(asset.valorContable),
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _ValueBox(
                          label: 'Amortizado',
                          value: moneyFmt.format(asset.amortizacionAcumulada),
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: AppColors.cardBorder,
                      color: asset.estaAmortizado
                          ? AppColors.success
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(pct * 100).toStringAsFixed(1)}% amortizado',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                      ),
                      Text(
                        '${asset.anosTranscurridos} de ${asset.vidaUtilAnos} años',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'Cuota mensual',
                    value: moneyFmt.format(asset.cuotaMensual),
                  ),
                  _InfoRow(
                    label: 'Cuota trimestral',
                    value: moneyFmt.format(asset.cuotaTrimestral),
                  ),
                  _InfoRow(
                    label: 'Cuota anual',
                    value: moneyFmt.format(asset.cuotaAnual),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tabla de amortización año a año
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tabla de amortización',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(2),
                      2: FlexColumnWidth(2),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                            color: AppColors.primary),
                        children: [
                          _tableHeader('Año'),
                          _tableHeader('Cuota'),
                          _tableHeader('Valor contable'),
                        ],
                      ),
                      ...List.generate(asset.vidaUtilAnos, (i) {
                        final ano = i + 1;
                        final cuota = asset.cuotaAnual;
                        final valorFin = (asset.importeTotal -
                                cuota * ano)
                            .clamp(asset.valorResidual, double.infinity);
                        final esActual =
                            ano == asset.anosTranscurridos + 1;
                        return TableRow(
                          decoration: BoxDecoration(
                            color: esActual
                                ? AppColors.primaryLight
                                : (i.isEven
                                    ? Colors.white
                                    : Colors.grey.shade50),
                          ),
                          children: [
                            _tableCell(
                                'Año $ano', TextAlign.center,
                                bold: esActual),
                            _tableCell(moneyFmt.format(cuota),
                                TextAlign.right,
                                bold: esActual),
                            _tableCell(moneyFmt.format(valorFin),
                                TextAlign.right,
                                bold: esActual),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Justificante
          if (asset.documentoPath != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.attach_file,
                    color: AppColors.primary),
                title: Text(
                  asset.documentoPath!.split('/').last,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Factura adjunta'),
                trailing: const Icon(Icons.open_in_new, size: 16),
                onTap: () => _openDocumento(buildContext, asset.documentoPath!),
              ),
            ),

          // Notas
          if (asset.notas != null && asset.notas!.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notas',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(asset.notas!),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Acciones
          if (asset.activo && !asset.estaAmortizado)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _darDeBaja(buildContext),
                icon: const Icon(Icons.archive_outlined,
                    color: AppColors.warning),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.warning,
                  side: const BorderSide(color: AppColors.warning),
                ),
                label: const Text('Dar de baja'),
              ),
            ),
          if (asset.activo && !asset.estaAmortizado)
            const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deleteAsset(buildContext),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              label: const Text('Eliminar inversión'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _openDocumento(BuildContext ctx, String path) {
    if (!File(path).existsSync()) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Archivo no encontrado')),
      );
    }
  }

  Future<void> _darDeBaja(BuildContext ctx) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('¿Dar de baja?'),
        content: const Text(
            'El activo dejará de incluirse en los cálculos de amortización. '
            'No se eliminan los datos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (confirm == true && ctx.mounted) {
      await ref.read(assetsProvider.notifier).darDeBaja(asset.id!);
      if (ctx.mounted) ctx.pop();
    }
  }

  Future<void> _deleteAsset(BuildContext ctx) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('¿Eliminar inversión?'),
        content: const Text(
            'Se eliminará permanentemente. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true && ctx.mounted) {
      await ref.read(assetsProvider.notifier).remove(asset.id!);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Inversión eliminada')),
        );
        ctx.pop();
      }
    }
  }

  Widget _tableHeader(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11),
            textAlign: TextAlign.center),
      );

  Widget _tableCell(String text, TextAlign align, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            textAlign: align),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ValueBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
