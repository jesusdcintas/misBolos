import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_strings.dart';
import '../../providers/client_provider.dart';
import '../../widgets/common/empty_state.dart';

class ClientsListScreen extends ConsumerStatefulWidget {
  const ClientsListScreen({super.key});

  @override
  ConsumerState<ClientsListScreen> createState() => _ClientsListScreenState();
}

class _ClientsListScreenState extends ConsumerState<ClientsListScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final clientsAsync = _searchQuery.isEmpty
        ? ref.watch(clientsProvider)
        : ref.watch(clientSearchProvider(_searchQuery));

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.clientes)),
      body: Column(
        children: [
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
              data: (clients) {
                if (clients.isEmpty) {
                  return const EmptyState(
                    icon: Icons.people_outline,
                    message: AppStrings.sinClientes,
                  );
                }
                return ListView.builder(
                  itemCount: clients.length,
                  itemBuilder: (context, index) {
                    final client = clients[index];
                    final displayName = client.alias.isNotEmpty ? client.alias : client.nombre;
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
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/client/${client.id}'),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/client/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
