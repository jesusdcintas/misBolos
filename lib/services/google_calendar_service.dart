import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;
import '../models/gig.dart';
import 'google_auth_service.dart';
import 'platform_auth_service.dart';

/// Servicio para sincronizar bolos con Google Calendar.
class GoogleCalendarService {
  static const String _calendarSummary = 'MisBolos';
  String? _calendarId;
  static const _calendarScopes = <String>[
    gcal.CalendarApi.calendarScope,
    gcal.CalendarApi.calendarEventsScope,
  ];

  Future<gcal.CalendarApi> _getApi() async {
    // En iOS/Android usamos google_sign_in y pedimos un token fresco.
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      var token = await PlatformAuthService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        await PlatformAuthService.instance.signInSilently();
        token = await PlatformAuthService.instance.getAccessToken();
      }
      if (token == null || token.isEmpty) {
        throw StateError(
          'Google Calendar no está conectado. Vuelve a conectar Google desde Perfil.',
        );
      }
      return _apiFromAccessToken(token);
    }

    // En macOS puede existir sesión Supabase sin provider token. Si no hay
    // token de proveedor, caemos al OAuth desktop persistido.
    if (!kIsWeb && Platform.isMacOS) {
      final token = await PlatformAuthService.instance.getAccessToken();
      if (token != null && token.isNotEmpty) {
        return _apiFromAccessToken(token);
      }
      await GoogleAuthService.instance.signInSilently();
      final desktopApi = GoogleAuthService.instance.calendarApi;
      if (desktopApi != null) return desktopApi;
      throw StateError(
        'Google Calendar no está conectado. Vuelve a conectar Google Calendar desde Perfil.',
      );
    }

    // En escritorio seguimos con el cliente OAuth persistido.
    var desktopApi = GoogleAuthService.instance.calendarApi;
    if (desktopApi == null) {
      await GoogleAuthService.instance.signInSilently();
      desktopApi = GoogleAuthService.instance.calendarApi;
    }
    if (desktopApi == null) {
      throw StateError('No hay sesión de Google activa');
    }
    return desktopApi;
  }

  gcal.CalendarApi _apiFromAccessToken(String token) {
    final creds = gauth.AccessCredentials(
      gauth.AccessToken(
        'Bearer',
        token,
        DateTime.now().toUtc().add(const Duration(minutes: 30)),
      ),
      null,
      _calendarScopes,
    );
    final client = gauth.authenticatedClient(http.Client(), creds);
    return gcal.CalendarApi(client);
  }

  /// Obtiene o crea el calendario "MisBolos" en la cuenta del usuario.
  Future<String> _ensureCalendar() async {
    if (_calendarId != null) return _calendarId!;

    final api = await _getApi();
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
    final api = await _getApi();
    final startDate = DateTime(gig.fecha.year, gig.fecha.month, gig.fecha.day);
    final endDate = startDate.add(const Duration(days: 1));

    final event = gcal.Event()
      ..summary = '🎧 Bolo: $clientName'
      ..description = _buildDescription(gig, cachet)
      ..start = gcal.EventDateTime(date: startDate)
      ..end = gcal.EventDateTime(date: endDate)
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
    final api = await _getApi();

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
    final api = await _getApi();

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
      case GigStatus.confirmado:
        return '9'; // azul
      case GigStatus.facturado:
        return '5'; // amarillo/naranja
      case GigStatus.confirmadoB:
      case GigStatus.realizadoB:
      case GigStatus.cobradoB:
        return '3'; // púrpura
      case GigStatus.cobrado:
        return '10'; // verde
      case GigStatus.cancelado:
        return '11'; // rojo
    }
  }

  Future<String?> _findEventByGigId(String calId, String gigId) async {
    final api = await _getApi();

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
