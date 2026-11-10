import '../../models/franja_bolo.dart';
import '../../models/gig.dart';

/// Un bolo, con la forma de la tabla `gigs` de Supabase.
///
/// `franja` solo se incluye si el bolo la tiene. Un upsert de PostgREST solo
/// escribe las columnas que vienen en el payload, así que un dispositivo que
/// todavía no conoce la franja de ese bolo no pisa la que hay en la nube. Es
/// el mismo criterio que ya se usaba con `deleted_at`.
Map<String, dynamic> gigToSupabase(Gig g, {String? userId}) => {
  'id': g.id,
  'user_id': userId,
  'fecha': g.fecha.toIso8601String().split('T').first,
  'client_id': g.clientId,
  'notas': g.notas,
  'cachet': g.cachet,
  'facturable': g.facturable,
  'status': g.status.dbValue,
  if (g.franja != null) 'franja': g.franja!.dbValue,
  'invoice_id': g.invoiceId,
  'created_at': g.createdAt.toUtc().toIso8601String(),
  'updated_at': g.updatedAt.toUtc().toIso8601String(),
  if (g.deletedAt != null)
    'deleted_at': g.deletedAt!.toUtc().toIso8601String(),
};

/// Un bolo leído de Supabase.
///
/// Una `franja` ausente o nula se queda en null, sin convertirla.
Gig gigFromSupabase(Map<String, dynamic> m) => Gig(
  id: m['id'],
  fecha: DateTime.parse(m['fecha']),
  clientId: m['client_id'] ?? '',
  notas: m['notas'],
  cachet: m['cachet'] != null ? (m['cachet'] as num).toDouble() : null,
  facturable: m['facturable'] ?? true,
  status: GigStatusExtension.fromDb(m['status'] ?? 'confirmado'),
  franja: franjaFromDb(m['franja'] as String?),
  invoiceId: m['invoice_id'],
  createdAt: DateTime.parse(m['created_at']),
  updatedAt: DateTime.parse((m['updated_at'] ?? m['created_at']).toString()),
  deletedAt: m['deleted_at'] != null
      ? DateTime.parse(m['deleted_at'].toString())
      : null,
);
