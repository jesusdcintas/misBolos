import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/client.dart';
import '../../models/gig.dart';
import '../../providers/client_provider.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_calendar_service.dart';

/// Lleva a Google Calendar el estado actual de [gig].
///
/// Si no hay sesión de Google no hace nada, y si falla la llamada se traga el
/// error: el calendario es un reflejo, no la fuente de la verdad, y una caída
/// de red no debe romper la acción que el usuario acaba de hacer.
Future<void> sincronizarBoloEnCalendario(WidgetRef ref, Gig gig) =>
    _sincronizar(ref.read, gig);

/// Lo mismo, pero desde dentro de un provider, que tiene otro tipo de `ref`.
Future<void> sincronizarBoloEnCalendarioDesdeProvider(Ref ref, Gig gig) =>
    _sincronizar(ref.read, gig);

Future<void> _sincronizar(
  T Function<T>(ProviderListenable<T>) leer,
  Gig gig,
) async {
  if (!leer(googleAuthProvider).isSignedIn) return;
  try {
    final client = await leer(clientByIdProvider(gig.clientId).future);
    await GoogleCalendarService().syncGig(
      gig: gig,
      clientName: client?.displayName ?? 'Cliente',
      cachet: gig.cachet,
    );
  } catch (_) {}
}
