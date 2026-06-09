import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../models/client.dart';
import '../../providers/client_provider.dart';
import '../../providers/gig_provider.dart';
import '../../providers/invoice_provider.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/skeleton_loading.dart';
import '../../core/utils/app_haptics.dart';

class ClientsListScreen extends ConsumerStatefulWidget {
  final bool embedded;
  const ClientsListScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ClientsListScreen> createState() => _ClientsListScreenState();
}

class _ClientsListScreenState extends ConsumerState<ClientsListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsProvider);
    final headerCount = clientsAsync.valueOrNull == null
        ? null
        : _filterClients(clientsAsync.valueOrNull!).length;

    final content = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                headerCount == null
                    ? AppStrings.clientes
                    : '${AppStrings.clientes} ($headerCount)',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar cliente...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: clientsAsync.when(
            data: (allClients) {
              final clients = _filterClients(allClients);
              if (clients.isEmpty) {
                return const EmptyState(
                  icon: Icons.people_outline,
                  message: AppStrings.sinClientes,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: clients.length,
                itemBuilder: (context, index) {
                  final client = clients[index];
                  final displayName = client.alias.isNotEmpty
                      ? client.alias
                      : client.nombre;
                  final subtitle = client.alias.isNotEmpty
                      ? '${client.nombre}${client.cifNif.isNotEmpty ? ' · ${client.cifNif}' : ''}'
                      : (client.cifNif.isNotEmpty ? client.cifNif : null);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(displayName[0].toUpperCase()),
                      ),
                      title: Text(displayName),
                      subtitle: subtitle != null ? Text(subtitle) : null,
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Opciones',
                        onSelected: (value) {
                          if (value == 'delete') {
                            _confirmDeleteClient(context, client);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline),
                                SizedBox(width: 8),
                                Text('Eliminar'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        AppHaptics.light();
                        context.push('/client/${client.id}');
                      },
                    ),
                  );
                },
              );
            },
            loading: () => Column(
              children: List.generate(6, (_) => const ClientCardSkeleton()),
            ),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Stack(
        children: [
          content,
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: () => context.push('/client/new'),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          headerCount == null
              ? AppStrings.clientes
              : '${AppStrings.clientes} ($headerCount)',
        ),
      ),
      body: content,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/client/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<Client> _filterClients(List<Client> clients) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return clients;
    return clients.where((client) {
      final haystacks = [
        client.nombre,
        client.alias,
        client.cifNif,
        ...client.aliases,
      ].map((value) => value.toLowerCase());
      return haystacks.any((value) => value.contains(query));
    }).toList();
  }

  Future<void> _confirmDeleteClient(BuildContext context, Client client) async {
    final gigs = await ref.read(gigsByClientProvider(client.id).future);
    final invoices = await ref.read(invoicesByClientProvider(client.id).future);
    if (!context.mounted) return;

    if (gigs.isNotEmpty || invoices.isNotEmpty) {
      final details = [
        if (gigs.isNotEmpty)
          '${gigs.length} bolo${gigs.length == 1 ? '' : 's'}',
        if (invoices.isNotEmpty)
          '${invoices.length} factura${invoices.length == 1 ? '' : 's'}',
      ].join(' y ');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No se puede eliminar'),
          content: Text(
            'Este cliente tiene $details asociados. Para evitar romper el historial, elimina o reasigna primero esos registros.',
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
          'Se eliminará "${client.nombre}". Esta acción no se puede deshacer.',
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
      await ref.read(clientsProvider.notifier).remove(client.id);
      ref.invalidate(clientsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cliente eliminado: ${client.nombre}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo eliminar: el cliente tiene datos relacionados.',
          ),
        ),
      );
    }
  }
}
