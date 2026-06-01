import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/gig.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/facturable_badge.dart';

class ClientDetailScreen extends ConsumerWidget {
  final String clientId;
  const ClientDetailScreen({super.key, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(clientByIdProvider(clientId));
    final gigsAsync = ref.watch(gigsByClientProvider(clientId));

    return clientAsync.when(
      data: (client) {
        if (client == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Cliente no encontrado')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(client.nombre),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  await context.push('/client/edit/${client.id}');
                  ref.invalidate(clientByIdProvider(client.id));
                  ref.invalidate(clientsProvider);
                },
              ),
              IconButton(
                tooltip: 'Eliminar cliente',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDeleteClient(
                  context: context,
                  ref: ref,
                  clientId: client.id,
                  clientName: client.nombre,
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Datos del cliente
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (client.cifNif.isNotEmpty)
                        _InfoRow(
                          label: AppStrings.cifNif,
                          value: client.cifNif,
                        ),
                      if (client.direccion.isNotEmpty)
                        _InfoRow(
                          label: AppStrings.direccion,
                          value: client.direccion,
                        ),
                      if (client.ciudad.isNotEmpty)
                        _InfoRow(
                          label: AppStrings.ciudad,
                          value: '${client.ciudad} ${client.codigoPostal}',
                        ),
                      if (client.provincia.isNotEmpty)
                        _InfoRow(label: 'Provincia', value: client.provincia),
                      if (client.email != null && client.email!.isNotEmpty)
                        _InfoRow(label: AppStrings.email, value: client.email!),
                      if (client.telefono != null &&
                          client.telefono!.isNotEmpty)
                        _InfoRow(
                          label: AppStrings.telefono,
                          value: client.telefono!,
                        ),
                      if (client.whatsappPhone != null &&
                          client.whatsappPhone!.isNotEmpty)
                        _InfoRow(
                          label: 'Teléfono WhatsApp',
                          value: client.whatsappPhone!,
                        ),
                      if (client.notas.isNotEmpty)
                        _InfoRow(label: 'Notas', value: client.notas),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Resumen financiero
              gigsAsync.when(
                data: (gigs) {
                  double totalOficial = 0;
                  double totalEnB = 0;
                  for (final g in gigs) {
                    final c = g.cachet ?? 0;
                    if (g.facturable && (g.status == GigStatus.cobrado)) {
                      totalOficial += c;
                    } else if (!g.facturable &&
                        g.status == GigStatus.cobradoB) {
                      totalEnB += c;
                    }
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: AppColors.accentGreen.withValues(alpha: 0.1),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                const Text(
                                  'Total facturado',
                                  style: TextStyle(fontSize: 12),
                                ),
                                Text(
                                  CurrencyFormatter.format(totalOficial),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.accentGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Card(
                          color: AppColors.accentPurple.withValues(alpha: 0.1),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                const Text(
                                  'Cobrado privado',
                                  style: TextStyle(fontSize: 12),
                                ),
                                Text(
                                  CurrencyFormatter.format(totalEnB),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.accentPurple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const SizedBox(),
                error: (_, __) => const SizedBox(),
              ),
              const SizedBox(height: 16),

              // Historial de bolos
              Text(
                'Historial de bolos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              gigsAsync.when(
                data: (gigs) {
                  if (gigs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Sin bolos registrados'),
                    );
                  }
                  return Column(
                    children: gigs
                        .map(
                          (g) => Card(
                            child: ListTile(
                              onTap: () => context.push('/gig/${g.id}'),
                              title: Text(DateFormatter.display(g.fecha)),
                              subtitle: g.cachet != null
                                  ? Text(CurrencyFormatter.format(g.cachet!))
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FacturableBadge(facturable: g.facturable),
                                  const SizedBox(width: 4),
                                  StatusBadge(
                                    status: g.status,
                                    facturable: g.facturable,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
              ),
            ],
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _confirmDeleteClient({
    required BuildContext context,
    required WidgetRef ref,
    required String clientId,
    required String clientName,
  }) async {
    final gigs = await ref.read(gigsByClientProvider(clientId).future);
    if (!context.mounted) return;

    if (gigs.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No se puede eliminar'),
          content: Text(
            'Este cliente tiene ${gigs.length} bolo(s) asociados. Para evitar romper el historial, elimina o reasigna primero esos bolos.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
          'Se eliminará "$clientName". Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(clientsProvider.notifier).remove(clientId);
      ref.invalidate(clientsProvider);
      ref.invalidate(clientByIdProvider(clientId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cliente eliminado: $clientName')));
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/finanzas');
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
