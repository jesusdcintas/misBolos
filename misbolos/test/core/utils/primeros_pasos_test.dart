import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/primeros_pasos.dart';
import 'package:misbolos/models/app_settings.dart';

AppSettings _settings({
  String nombre = '',
  String nif = '',
  String direccion = '',
}) => AppSettings(
  emisorNombre: nombre,
  emisorNIF: nif,
  emisorDireccion: direccion,
);

List<EstadoPasoInicial> _pasos({
  AppSettings? settings,
  bool google = false,
  bool clientes = false,
  bool bolos = false,
  bool facturas = false,
}) => primerosPasos(
  settings: settings,
  googleConectado: google,
  hayClientes: clientes,
  hayBolos: bolos,
  hayFacturas: facturas,
);

bool _hecho(List<EstadoPasoInicial> pasos, PasoInicial paso) =>
    pasos.firstWhere((p) => p.paso == paso).completado;

void main() {
  group('datos fiscales', () {
    test('hacen falta nombre, NIF y dirección', () {
      expect(datosFiscalesCompletos(null), isFalse);
      expect(datosFiscalesCompletos(_settings()), isFalse);
      expect(
        datosFiscalesCompletos(_settings(nombre: 'Jesús', nif: '12345678Z')),
        isFalse,
      );
      expect(
        datosFiscalesCompletos(
          _settings(nombre: 'Jesús', nif: '12345678Z', direccion: 'Calle 1'),
        ),
        isTrue,
      );
    });

    test('los espacios en blanco no cuentan', () {
      expect(
        datosFiscalesCompletos(
          _settings(nombre: '  ', nif: '12345678Z', direccion: 'Calle 1'),
        ),
        isFalse,
      );
    });
  });

  group('primeros pasos', () {
    test('de entrada no hay ninguno hecho', () {
      final pasos = _pasos();

      expect(pasos.length, 5);
      expect(pasosCompletados(pasos), 0);
      expect(primerosPasosTerminados(pasos), isFalse);
      expect(pasos.map((p) => p.paso), PasoInicial.values);
    });

    test('cada señal marca su paso y solo el suyo', () {
      expect(_hecho(_pasos(clientes: true), PasoInicial.cliente), isTrue);
      expect(_hecho(_pasos(clientes: true), PasoInicial.bolo), isFalse);
      expect(_hecho(_pasos(bolos: true), PasoInicial.bolo), isTrue);
      expect(_hecho(_pasos(facturas: true), PasoInicial.factura), isTrue);
      expect(_hecho(_pasos(google: true), PasoInicial.google), isTrue);
      expect(
        _hecho(
          _pasos(
            settings: _settings(
              nombre: 'Jesús',
              nif: '12345678Z',
              direccion: 'Calle 1',
            ),
          ),
          PasoInicial.datosFiscales,
        ),
        isTrue,
      );
    });

    test('con todo hecho, la tarjeta sobra', () {
      final pasos = _pasos(
        settings: _settings(
          nombre: 'Jesús',
          nif: '12345678Z',
          direccion: 'Calle 1',
        ),
        google: true,
        clientes: true,
        bolos: true,
        facturas: true,
      );

      expect(pasosCompletados(pasos), 5);
      expect(primerosPasosTerminados(pasos), isTrue);
    });

    test('los datos fiscales y Google llevan a Perfil', () {
      expect(PasoInicial.datosFiscales.ruta, '/profile');
      expect(PasoInicial.google.ruta, '/profile');
      expect(PasoInicial.cliente.ruta, '/client/new');
      expect(PasoInicial.bolo.ruta, '/gig/new');
      expect(PasoInicial.factura.ruta, '/calendar');
    });
  });
}
