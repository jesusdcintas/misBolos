import 'package:googleapis/calendar/v3.dart' as gcal;
import '../models/gig.dart';
import 'google_auth_service.dart';

/// Servicio para sincronizar bolos con Google Calendar.
class GoogleCalendarService {
  static const String _calendarSummary = 'MisBolos';
  String? _calendarId;

  /// Obtiene o crea el calendario "MisBolos" en la cuenta del usuario.
  Future<String> _ensureCalendar() async {
    if (_calendarId != null) return _calendarId!;

    final api = GoogleAuthService.instance.calendarApi;
    if (api == null) throw StateError('No hay sesión de Google activa');
    final list = await api.calendarList.list();

    // Buscar calendario existente
    for (final entry in list.items ?? []) {
      if (entry.summary == _calendarSummary) {
        _calendarId = entry.id;
        return _calendarId!;
      }
    }

    // Crear nuevo calendario
    final newCal = gcal.Calendar()..summary = _calendarSummary;
    final created = await api.calendars.insert(newCal);
    _calendarId = created.id!;
    return _calendarId!;
  }

  /// Crea o actualiza un evento en Google Calendar para un bolo.
  Future<void> syncGig({
    required Gig gig,
    required String clientName,
    required double? cachet,
  }) async {

    final calId = await _ensureCalendar();
    final api = GoogleAuthService.instance.calendarApi!;

    final event = gcal.Event()
      ..summary = '🎧 Bolo: $clientName'
      ..description = _buildDescription(gig, cachet)
      ..start = gcal.EventDateTime(
        date: DateTime(gig.fecha.year, gig.fecha.month, gig.fecha.day),
      )
      ..end = gcal.EventDateTime(
        date: DateTime(gig.fecha.year, gig.fecha.month, gig.fecha.day + 1),
      )
      ..extendedProperties = gcal.EventExtendedProperties(
        private: {'misbolos_gig_id': gig.id},
      );

    // Color por estado
    event.colorId = _colorIdForStatus(gig.status);

    // Buscar evento existente para este bolo
    final existingId = await _findEventByGigId(calId, gig.id);

    if (existingId != null) {
      await api.events.update(event, calId, existingId);
    } else {
      await api.events.insert(event, calId);
    }
  }

  /// Elimina el evento de un bolo de Google Calendar.
  Future<void> deleteGig(String gigId) async {
    final calId = await _ensureCalendar();
    final api = GoogleAuthService.instance.calendarApi!;

    final existingId = await _findEventByGigId(calId, gigId);
    if (existingId != null) {
      await api.events.delete(calId, existingId);
    }
  }

  /// Obtiene todos los eventos del calendario MisBolos.
  Future<List<gcal.Event>> getEvents({
    required DateTime from,
    required DateTime to,
  }) async {
    final calId = await _ensureCalendar();
    final api = GoogleAuthService.instance.calendarApi!;

    final events = await api.events.list(
      calId,
      timeMin: from.toUtc(),
      timeMax: to.toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
    );

    return events.items ?? [];
  }

  String _buildDescription(Gig gig, double? cachet) {
    final lines = <String>[];
    if (cachet != null) lines.add('Caché: ${cachet.toStringAsFixed(2)} €');
    lines.add('Estado: ${gig.status.label}');
    if (gig.notas != null && gig.notas!.isNotEmpty) {
      lines.add('Notas: ${gig.notas}');
    }
    return lines.join('\n');
  }

  /// Mapeo de estado a colorId de Google Calendar.
  /// Ref: https://developers.google.com/calendar/api/v3/reference/colors
  String _colorIdForStatus(GigStatus status) {
    switch (status) {
      case GigStatus.pendiente:
        return '9'; // azul
      case GigStatus.facturaGenerada:
        return '7'; // cyan
      case GigStatus.facturaEnviada:
        return '5'; // amarillo/naranja
      case GigStatus.pagado:
        return '10'; // verde
      case GigStatus.cancelado:
        return '11'; // rojo
      case GigStatus.cobradoEnB:
        return '3'; // púrpura (no debería llegar aquí)
    }
  }

  Future<String?> _findEventByGigId(String calId, String gigId) async {
    final api = GoogleAuthService.instance.calendarApi!;

    try {
      final events = await api.events.list(
        calId,
        privateExtendedProperty: ['misbolos_gig_id=$gigId'],
        singleEvents: true,
      );

      if (events.items != null && events.items!.isNotEmpty) {
        return events.items!.first.id;
      }
    } catch (_) {}

    return null;
  }
}
