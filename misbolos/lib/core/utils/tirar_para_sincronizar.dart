import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sync_provider.dart';
import '../services/hapticos.dart';

/// Sincronización de tirar hacia abajo, igual en todas las pantallas.
///
/// Llama a la misma `syncAll` que el resto de la app: aquí no hay lógica de
/// sincronización propia. Si falla, avisa con el mensaje que deje el propio
/// sync y los datos locales se quedan como estaban.
Future<void> sincronizarTirando(BuildContext context, WidgetRef ref) async {
  Hapticos.toque();
  final messenger = ScaffoldMessenger.of(context);

  await ref.read(syncProvider.notifier).syncAll(reason: 'pull_to_refresh');

  final estado = ref.read(syncProvider);
  if (estado.status != SyncStatus.error) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        estado.message ?? 'No se pudieron sincronizar algunos datos',
      ),
    ),
  );
}
