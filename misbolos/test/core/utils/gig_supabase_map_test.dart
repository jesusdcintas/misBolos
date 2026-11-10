import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/gig_supabase_map.dart';
import 'package:misbolos/models/franja_bolo.dart';
import 'package:misbolos/models/gig.dart';

Gig _gig({FranjaBolo? franja}) => Gig(
  id: 'bolo-1',
  fecha: DateTime(2026, 11, 14),
  clientId: 'cliente-1',
  cachet: 500,
  franja: franja,
  createdAt: DateTime.utc(2026, 11, 1, 10),
  updatedAt: DateTime.utc(2026, 11, 2, 10),
);

void main() {
  group('gigToSupabase', () {
    test('con franja la incluye con su valor guardado', () {
      final map = gigToSupabase(_gig(franja: FranjaBolo.noche));
      expect(map.containsKey('franja'), isTrue);
      expect(map['franja'], 'noche');
    });

    test('incluye los tres valores posibles', () {
      expect(
        gigToSupabase(_gig(franja: FranjaBolo.tarde))['franja'],
        'tarde',
      );
      expect(
        gigToSupabase(_gig(franja: FranjaBolo.diaCompleto))['franja'],
        'dia_completo',
      );
    });

    test('sin franja la clave no aparece, para no pisar la de la nube', () {
      final map = gigToSupabase(_gig());
      expect(map.containsKey('franja'), isFalse);
    });

    test('el resto de campos no cambia', () {
      final map = gigToSupabase(_gig(), userId: 'usuario-1');
      expect(map['id'], 'bolo-1');
      expect(map['user_id'], 'usuario-1');
      expect(map['fecha'], '2026-11-14');
      expect(map['client_id'], 'cliente-1');
      expect(map['cachet'], 500);
      expect(map['status'], 'confirmado');
      expect(map['facturable'], isTrue);
      // deleted_at sigue el mismo criterio que franja.
      expect(map.containsKey('deleted_at'), isFalse);
    });
  });

  group('gigFromSupabase', () {
    Map<String, dynamic> fila({Object? franja = 'ausente'}) => {
      'id': 'bolo-1',
      'fecha': '2026-11-14',
      'client_id': 'cliente-1',
      'cachet': 500,
      'facturable': true,
      'status': 'confirmado',
      'created_at': '2026-11-01T10:00:00Z',
      'updated_at': '2026-11-02T10:00:00Z',
      if (franja != 'ausente') 'franja': franja,
    };

    test('lee la franja guardada', () {
      expect(gigFromSupabase(fila(franja: 'tarde')).franja, FranjaBolo.tarde);
      expect(gigFromSupabase(fila(franja: 'noche')).franja, FranjaBolo.noche);
      expect(
        gigFromSupabase(fila(franja: 'dia_completo')).franja,
        FranjaBolo.diaCompleto,
      );
    });

    test('un null se lee como null, sin convertirlo', () {
      expect(gigFromSupabase(fila(franja: null)).franja, isNull);
    });

    test('una fila sin la columna se lee como null', () {
      expect(gigFromSupabase(fila()).franja, isNull);
    });

    test('ida y vuelta: la franja se conserva', () {
      final original = _gig(franja: FranjaBolo.noche);
      final map = gigToSupabase(original, userId: 'u1')
        ..remove('user_id');
      expect(gigFromSupabase(map).franja, FranjaBolo.noche);
    });

    test('ida y vuelta sin franja: sigue en null', () {
      final map = gigToSupabase(_gig(), userId: 'u1')..remove('user_id');
      expect(gigFromSupabase(map).franja, isNull);
    });
  });
}
