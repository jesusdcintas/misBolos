import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/estado_tutorial.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<EstadoTutorial> _estado([Map<String, Object> inicial = const {}]) async {
  SharedPreferences.setMockInitialValues(inicial);
  return EstadoTutorial(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('qué tours se han visto', () {
    test('de entrada no hay ninguno visto ni decidido', () async {
      final estado = await _estado();
      final datos = estado.datos;

      expect(datos.decidido, isFalse);
      expect(datos.vistos, isEmpty);
      expect(datos.tarjetaOculta, isFalse);
      // Sin decidir no salta nada, aunque el tour esté sin ver.
      expect(datos.tocaMostrar(Tour.inicio), isFalse);
      expect(datos.tarjetaVisible, isFalse);
    });

    test('marcar uno como visto no toca los demás', () async {
      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.usuarioNuevo);
      await estado.marcarVisto(Tour.agenda);

      final datos = estado.datos;
      expect(datos.estaVisto(Tour.agenda), isTrue);
      expect(datos.tocaMostrar(Tour.agenda), isFalse);
      for (final otro in Tour.values.where((t) => t != Tour.agenda)) {
        expect(datos.estaVisto(otro), isFalse, reason: otro.name);
        expect(datos.tocaMostrar(otro), isTrue, reason: otro.name);
      }
    });

    test('repetir el tutorial lo devuelve todo al primer día', () async {
      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.usuarioExistente);
      expect(estado.datos.vistos.length, Tour.values.length);

      await estado.repetirTutorial();
      final datos = estado.datos;

      expect(datos.vistos, isEmpty);
      expect(datos.tarjetaOculta, isFalse);
      expect(datos.tarjetaVisible, isTrue);
      // La decisión se mantiene: si se borrara, volvería a marcarlo todo visto.
      expect(datos.decidido, isTrue);
    });

    test('ocultar la tarjeta no afecta a los tours', () async {
      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.usuarioNuevo);
      await estado.ocultarTarjeta();

      expect(estado.datos.tarjetaVisible, isFalse);
      expect(estado.datos.tocaMostrar(Tour.inicio), isTrue);
    });
  });

  group('la guía de inicio', () {
    test('saltarse un paso no toca los demás', () async {
      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.usuarioNuevo);

      await estado.saltarPaso(PasoGuia.carpetas);

      expect(estado.datos.pasosSaltados, {PasoGuia.carpetas});
    });

    test('los eventos de la guía se apuntan', () async {
      final estado = await _estado();
      expect(estado.datos.numeracionRevisada, isFalse);
      expect(estado.datos.facturaCompartida, isFalse);

      await estado.marcarNumeracionRevisada();
      await estado.marcarFacturaCompartida();

      expect(estado.datos.numeracionRevisada, isTrue);
      expect(estado.datos.facturaCompartida, isTrue);
    });

    test('repetir la guía borra pasos saltados y eventos', () async {
      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.usuarioNuevo);
      await estado.saltarPaso(PasoGuia.gasto);
      await estado.marcarNumeracionRevisada();
      await estado.marcarFacturaCompartida();
      await estado.ocultarTarjeta();

      await estado.repetirTutorial();

      final datos = estado.datos;
      expect(datos.pasosSaltados, isEmpty);
      expect(datos.numeracionRevisada, isFalse);
      expect(datos.facturaCompartida, isFalse);
      expect(datos.tarjetaVisible, isTrue);
      expect(datos.vistos, isEmpty);
    });
  });

  group('el encargo de tour', () {
    test('vale para la pantalla a la que se manda al usuario', () async {
      final estado = await _estado();
      await estado.encargarTour(Tour.perfil);

      final datos = estado.datos;
      expect(datos.encargoVigente(Tour.perfil), isTrue);
      expect(datos.encargoVigente(Tour.ajustes), isFalse);
    });

    test('caduca a los pocos minutos', () async {
      final estado = await _estado();
      await estado.encargarTour(Tour.perfil);
      final datos = estado.datos;

      // Al rato ya no salta por sorpresa.
      final despues = DateTime.now().add(const Duration(minutes: 5));
      expect(datos.encargoVigente(Tour.perfil, ahora: despues), isFalse);
    });

    test('olvidarlo lo deja sin efecto al momento', () async {
      final estado = await _estado();
      await estado.encargarTour(Tour.perfil);

      await estado.olvidarEncargo();

      expect(estado.datos.tourPendiente, isNull);
      expect(estado.datos.encargoVigente(Tour.perfil), isFalse);
    });

    test('sin encargo, ningún tour salta solo', () async {
      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.usuarioNuevo);

      for (final tour in Tour.values) {
        expect(estado.datos.encargoVigente(tour), isFalse, reason: tour.name);
      }
    });
  });

  group('usuario nuevo o de los de antes', () {
    DecisionTutorial decidir({
      bool yaDecidido = false,
      bool conSesion = true,
      DateTime? ultimaDescargaNube,
      bool datosCargados = true,
      bool tieneDatos = false,
    }) => decidirInicioTutorial(
      yaDecidido: yaDecidido,
      conSesion: conSesion,
      ultimaDescargaNube: ultimaDescargaNube,
      datosCargados: datosCargados,
      tieneDatos: tieneDatos,
    );

    test('dispositivo nuevo con datos en la nube: no ve los tours', () async {
      // Antes de la descarga la cuenta parece vacía: no se decide nada.
      expect(
        decidir(ultimaDescargaNube: null, tieneDatos: false),
        DecisionTutorial.esperar,
      );

      // Con la descarga hecha ya se ven sus bolos: es de los de antes.
      expect(
        decidir(ultimaDescargaNube: DateTime(2026, 11, 16), tieneDatos: true),
        DecisionTutorial.usuarioExistente,
      );

      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.usuarioExistente);
      final datos = estado.datos;
      expect(datos.decidido, isTrue);
      expect(datos.vistos.length, Tour.values.length);
      expect(datos.tarjetaVisible, isFalse);
      for (final tour in Tour.values) {
        expect(datos.tocaMostrar(tour), isFalse, reason: tour.name);
      }
    });

    test('cuenta nueva: sí los ve', () async {
      expect(
        decidir(ultimaDescargaNube: DateTime(2026, 11, 16), tieneDatos: false),
        DecisionTutorial.usuarioNuevo,
      );

      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.usuarioNuevo);
      final datos = estado.datos;
      expect(datos.decidido, isTrue);
      expect(datos.vistos, isEmpty);
      expect(datos.tarjetaVisible, isTrue);
      expect(datos.tocaMostrar(Tour.inicio), isTrue);
    });

    test('invitado: se decide con lo que hay en el dispositivo', () {
      // Sin sesión no hay nube que esperar.
      expect(
        decidir(conSesion: false, ultimaDescargaNube: null, tieneDatos: false),
        DecisionTutorial.usuarioNuevo,
      );
      expect(
        decidir(conSesion: false, ultimaDescargaNube: null, tieneDatos: true),
        DecisionTutorial.usuarioExistente,
      );
      // Pero sí se espera a que carguen los datos del dispositivo.
      expect(
        decidir(conSesion: false, datosCargados: false),
        DecisionTutorial.esperar,
      );
    });

    test('si la descarga falla no se decide y se reintenta luego', () async {
      final estado = await _estado();
      await estado.aplicarDecision(DecisionTutorial.esperar);

      // Nada escrito: en la siguiente apertura se vuelve a mirar.
      expect(estado.datos.decidido, isFalse);
    });

    test('una vez decidido no se vuelve a decidir', () {
      expect(
        decidir(yaDecidido: true, tieneDatos: true),
        DecisionTutorial.esperar,
      );
    });
  });
}
