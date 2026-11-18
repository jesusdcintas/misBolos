import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/services/guia_inicio.dart';
import 'package:misbolos/models/app_settings.dart';

/// Señales de alguien que acaba de instalar la app.
const _recienLlegado = SenalesGuia();

/// Señales de quien lo tiene todo hecho.
const _todoHecho = SenalesGuia(
  googleConectado: true,
  carpetasCreadas: true,
  primeraSincronizacionCompleta: true,
  datosFacturacionCompletos: true,
  numeracionRevisada: true,
  hayClientes: true,
  hayBolos: true,
  hayFacturas: true,
  facturaCompartida: true,
  hayFacturaEmitida: true,
  hayFacturaCobrada: true,
  hayGastoOInversion: true,
);

EstadoPasoGuia _estadoDe(List<EstadoPasoGuia> pasos, PasoGuia paso) =>
    pasos.firstWhere((p) => p.paso == paso);

void main() {
  group('los pasos de la guía', () {
    test('son doce y van en el orden del flujo real', () {
      final pasos = pasosDeLaGuia(_recienLlegado);

      expect(pasos.length, 12);
      expect(pasos.map((p) => p.paso).toList(), [
        PasoGuia.google,
        PasoGuia.carpetas,
        PasoGuia.sincronizacion,
        PasoGuia.datosFacturacion,
        PasoGuia.numeracion,
        PasoGuia.cliente,
        PasoGuia.bolo,
        PasoGuia.factura,
        PasoGuia.compartir,
        PasoGuia.facturada,
        PasoGuia.cobrada,
        PasoGuia.gasto,
      ]);
    });

    test('de entrada no hay ninguno hecho', () {
      final pasos = pasosDeLaGuia(_recienLlegado);

      expect(pasosCerrados(pasos), 0);
      expect(siguientePaso(pasos), PasoGuia.google);
      expect(guiaTerminada(pasos), isFalse);
    });

    test('cada señal cierra su paso y solo el suyo', () {
      void comprobar(SenalesGuia senales, PasoGuia esperado) {
        final pasos = pasosDeLaGuia(senales);
        expect(_estadoDe(pasos, esperado).hecho, isTrue, reason: esperado.name);
        expect(pasosCerrados(pasos), 1, reason: esperado.name);
      }

      comprobar(const SenalesGuia(googleConectado: true), PasoGuia.google);
      comprobar(const SenalesGuia(carpetasCreadas: true), PasoGuia.carpetas);
      comprobar(
        const SenalesGuia(primeraSincronizacionCompleta: true),
        PasoGuia.sincronizacion,
      );
      comprobar(
        const SenalesGuia(datosFacturacionCompletos: true),
        PasoGuia.datosFacturacion,
      );
      comprobar(
        const SenalesGuia(numeracionRevisada: true),
        PasoGuia.numeracion,
      );
      comprobar(const SenalesGuia(hayClientes: true), PasoGuia.cliente);
      comprobar(const SenalesGuia(hayBolos: true), PasoGuia.bolo);
      comprobar(const SenalesGuia(hayFacturas: true), PasoGuia.factura);
      comprobar(const SenalesGuia(facturaCompartida: true), PasoGuia.compartir);
      comprobar(const SenalesGuia(hayFacturaEmitida: true), PasoGuia.facturada);
      comprobar(const SenalesGuia(hayFacturaCobrada: true), PasoGuia.cobrada);
      comprobar(const SenalesGuia(hayGastoOInversion: true), PasoGuia.gasto);
    });

    test('la sincronización en marcha se enseña aparte de estar hecha', () {
      final enMarcha = pasosDeLaGuia(const SenalesGuia(sincronizando: true));
      expect(_estadoDe(enMarcha, PasoGuia.sincronizacion).enCurso, isTrue);
      expect(_estadoDe(enMarcha, PasoGuia.sincronizacion).hecho, isFalse);

      // Cuando termina, deja de estar «en curso».
      final terminada = pasosDeLaGuia(
        const SenalesGuia(
          sincronizando: true,
          primeraSincronizacionCompleta: true,
        ),
      );
      expect(_estadoDe(terminada, PasoGuia.sincronizacion).enCurso, isFalse);
      expect(_estadoDe(terminada, PasoGuia.sincronizacion).hecho, isTrue);
    });
  });

  group('el siguiente paso', () {
    test('salta los que ya están hechos', () {
      final pasos = pasosDeLaGuia(
        const SenalesGuia(googleConectado: true, carpetasCreadas: true),
      );

      expect(pasosCerrados(pasos), 2);
      expect(siguientePaso(pasos), PasoGuia.sincronizacion);
    });

    test('un paso saltado cuenta como cerrado y no vuelve a salir', () {
      final pasos = pasosDeLaGuia(
        const SenalesGuia(saltados: {PasoGuia.google, PasoGuia.carpetas}),
      );

      expect(_estadoDe(pasos, PasoGuia.google).saltado, isTrue);
      expect(_estadoDe(pasos, PasoGuia.google).hecho, isFalse);
      expect(pasosCerrados(pasos), 2);
      expect(siguientePaso(pasos), PasoGuia.sincronizacion);
    });

    test('con todo cerrado, la guía termina', () {
      final pasos = pasosDeLaGuia(_todoHecho);

      expect(pasosCerrados(pasos), 12);
      expect(siguientePaso(pasos), isNull);
      expect(guiaTerminada(pasos), isTrue);
    });

    test('saltarse el último también termina la guía', () {
      final pasos = pasosDeLaGuia(
        const SenalesGuia(
          googleConectado: true,
          carpetasCreadas: true,
          primeraSincronizacionCompleta: true,
          datosFacturacionCompletos: true,
          numeracionRevisada: true,
          hayClientes: true,
          hayBolos: true,
          hayFacturas: true,
          facturaCompartida: true,
          hayFacturaEmitida: true,
          hayFacturaCobrada: true,
          saltados: {PasoGuia.gasto},
        ),
      );

      expect(guiaTerminada(pasos), isTrue);
    });
  });

  group('los datos de facturación', () {
    AppSettings ajustes({
      String nombre = '',
      String nif = '',
      String direccion = '',
    }) => AppSettings(
      emisorNombre: nombre,
      emisorNIF: nif,
      emisorDireccion: direccion,
    );

    test('hacen falta nombre, NIF y dirección; el logo no', () {
      expect(datosFiscalesCompletos(null), isFalse);
      expect(datosFiscalesCompletos(ajustes()), isFalse);
      expect(
        datosFiscalesCompletos(ajustes(nombre: 'Jesús', nif: '12345678Z')),
        isFalse,
      );
      expect(
        datosFiscalesCompletos(
          ajustes(nombre: 'Jesús', nif: '12345678Z', direccion: 'Calle 1'),
        ),
        isTrue,
      );
    });

    test('los espacios en blanco no cuentan', () {
      expect(
        datosFiscalesCompletos(
          ajustes(nombre: '   ', nif: '12345678Z', direccion: 'Calle 1'),
        ),
        isFalse,
      );
    });
  });

  group('a dónde lleva «Hacerlo ahora»', () {
    test('los primeros pasos van a Perfil y a Ajustes', () {
      expect(destinoDelPaso(PasoGuia.google).ruta, '/profile');
      expect(destinoDelPaso(PasoGuia.carpetas).ruta, '/profile');
      expect(destinoDelPaso(PasoGuia.datosFacturacion).tour, Tour.perfil);
      expect(destinoDelPaso(PasoGuia.numeracion).ruta, '/settings');
    });

    test('la factura se hace desde el bolo que falta por facturar', () {
      final destino = destinoDelPaso(
        PasoGuia.factura,
        boloSinFacturaId: 'bolo-7',
      );

      expect(destino.ruta, '/gig/bolo-7');
      expect(destino.tour, Tour.boloAFacturar);
      expect(destino.aviso, isNull);
    });

    test('sin ese bolo, lleva a la agenda y lo explica', () {
      final destino = destinoDelPaso(PasoGuia.factura);

      expect(destino.ruta, '/calendar');
      expect(destino.aviso, isNotNull);
      expect(destino.aviso, contains('genera su factura'));
    });

    test('compartir, emitir y cobrar abren la misma factura', () {
      for (final (paso, tour) in [
        (PasoGuia.compartir, Tour.facturaCompartir),
        (PasoGuia.facturada, Tour.facturaEmitir),
        (PasoGuia.cobrada, Tour.facturaCobrar),
      ]) {
        final destino = destinoDelPaso(paso, facturaRecienteId: 'fac-3');
        expect(destino.ruta, '/invoice/fac-3', reason: paso.name);
        expect(destino.tour, tour, reason: paso.name);
      }
    });

    test('sin factura, llevan a la lista con un aviso', () {
      final destino = destinoDelPaso(PasoGuia.cobrada);

      expect(destino.ruta, '/finanzas');
      expect(destino.aviso, contains('Ábrela desde la lista'));
    });

    test('el gasto lleva a la pestaña de Gastos con su tour', () {
      final destino = destinoDelPaso(PasoGuia.gasto);

      // A la pestaña de Gastos de Finanzas, no al formulario suelto: así el
      // tour tiene montado el botón de añadir al que señalar.
      expect(destino.ruta, '/finanzas?tab=gastos');
      expect(destino.tour, Tour.gastos);
    });

    test('cada paso tiene título y explicación', () {
      for (final paso in PasoGuia.values) {
        expect(paso.titulo, isNotEmpty, reason: paso.name);
        expect(paso.detalle, isNotEmpty, reason: paso.name);
      }
    });
  });
}
