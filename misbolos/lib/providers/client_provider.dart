import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/client.dart';
import '../repositories/client_repository.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';

final clientRepositoryProvider = Provider((ref) => ClientRepository.instance);

final clientsProvider = AsyncNotifierProvider<ClientsNotifier, List<Client>>(
  ClientsNotifier.new,
);

class ClientsNotifier extends AsyncNotifier<List<Client>> {
  @override
  Future<List<Client>> build() async {
    return ref.read(clientRepositoryProvider).getAll();
  }

  Future<void> add(Client client) async {
    await ref.read(clientRepositoryProvider).insert(client);
    try {
      await SupabaseService.instance.uploadClients([client]);
    } catch (e) {
      debugPrint('[ClientProvider] Supabase upload failed: $e');
    }
    ref.invalidateSelf();
  }

  Future<void> updateClient(Client client) async {
    await ref.read(clientRepositoryProvider).update(client);
    try {
      await SupabaseService.instance.uploadClients([client]);
    } catch (e) {
      debugPrint('[ClientProvider] Supabase upload failed: $e');
    }
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(clientRepositoryProvider).delete(id);
    try {
      await SupabaseService.instance.deleteClient(id);
    } catch (e) {
      debugPrint('[ClientProvider] Supabase delete failed, queuing: $e');
      await DatabaseHelper.instance.addPendingDeletion('clients', id);
    }
    ref.invalidateSelf();
  }
}

final clientByIdProvider = FutureProvider.family<Client?, String>((ref, id) {
  return ref.read(clientRepositoryProvider).getById(id);
});

final clientSearchProvider = FutureProvider.family<List<Client>, String>((
  ref,
  query,
) {
  if (query.isEmpty) return ref.read(clientRepositoryProvider).getAll();
  return ref.read(clientRepositoryProvider).search(query);
});
