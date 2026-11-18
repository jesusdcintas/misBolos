import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/guia_inicio.dart';
import '../models/invoice.dart';
import 'assets_provider.dart';
import 'client_provider.dart';
import 'estado_drive_provider.dart';
import 'expenses_provider.dart';
import 'gig_provider.dart';
import 'invoice_provider.dart';
import 'settings_provider.dart';
import '../services/google_auth_service.dart';
import 'sync_provider.dart';
import 'tutorial_provider.dart';

/// Los doce pasos de la guía con lo que la app sabe ahora mismo.
final guiaInicioProvider = Provider<List<EstadoPasoGuia>>((ref) {
  final tutorial = ref.watch(tutorialProvider).valueOrNull;
  final drive = ref.watch(estadoDriveProvider).valueOrNull;
  final facturas = ref.watch(invoicesProvider).valueOrNull ?? const <Invoice>[];

  return pasosDeLaGuia(
    SenalesGuia(
      googleConectado: ref.watch(googleAuthProvider).isSignedIn,
      carpetasCreadas: drive?.carpetasCreadas ?? false,
      primeraSincronizacionCompleta:
          drive?.primeraSincronizacionCompleta ?? false,
      sincronizando: ref.watch(syncProvider).status == SyncStatus.syncing,
      datosFacturacionCompletos: datosFiscalesCompletos(
        ref.watch(settingsProvider).valueOrNull,
      ),
      numeracionRevisada: tutorial?.numeracionRevisada ?? false,
      hayClientes: ref.watch(clientsProvider).valueOrNull?.isNotEmpty ?? false,
      hayBolos: ref.watch(gigsProvider).valueOrNull?.isNotEmpty ?? false,
      hayFacturas: facturas.isNotEmpty,
      facturaCompartida: tutorial?.facturaCompartida ?? false,
      hayFacturaEmitida: facturas.any(
        (f) => f.status != InvoiceStatus.borrador,
      ),
      hayFacturaCobrada: facturas.any((f) => f.status == InvoiceStatus.pagada),
      hayGastoOInversion:
          (ref.watch(expensesProvider).valueOrNull?.isNotEmpty ?? false) ||
          (ref.watch(assetsProvider).valueOrNull?.isNotEmpty ?? false),
      saltados: tutorial?.pasosSaltados ?? const {},
      modoRepaso: tutorial?.modoRepaso ?? false,
      pasosRepaso: tutorial?.pasosRepaso ?? const {},
    ),
  );
});

/// Si la guía se puede enseñar: decidida, no oculta y con algo por hacer.
final guiaVisibleProvider = Provider<bool>((ref) {
  final tutorial = ref.watch(tutorialProvider).valueOrNull;
  if (tutorial == null || !tutorial.tarjetaVisible) return false;
  return true;
});

/// El bolo más reciente que todavía no tiene factura.
final boloSinFacturaProvider = Provider<String?>((ref) {
  final bolos = [...?ref.watch(gigsProvider).valueOrNull]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  for (final bolo in bolos) {
    if (bolo.deletedAt != null) continue;
    if (bolo.invoiceId?.trim().isNotEmpty ?? false) continue;
    return bolo.id;
  }
  return null;
});

/// La factura más reciente, que es con la que va la guía.
final facturaRecienteProvider = Provider<String?>((ref) {
  final facturas = [...?ref.watch(invoicesProvider).valueOrNull]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return facturas.isEmpty ? null : facturas.first.id;
});
