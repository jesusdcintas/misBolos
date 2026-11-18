import 'package:flutter/foundation.dart';

import '../../models/app_settings.dart';

/// Cada tramo del tutorial: los de pantalla completa y los cortos que lanza
/// la guía para señalar un solo elemento.
enum Tour {
  inicio,
  agenda,
  nuevoBolo,
  facturas,
  gastos,
  perfil,
  ajustes,
  nuevoCliente,
  boloAFacturar,
  facturaCompartir,
  facturaEmitir,
  facturaCobrar,
}

/// Los pasos de la guía de inicio, en el orden en que se hacen.
enum PasoGuia {
  google,
  carpetas,
  sincronizacion,
  datosFacturacion,
  numeracion,
  cliente,
  bolo,
  factura,
  compartir,
  facturada,
  cobrada,
  gasto,
}

extension PasoGuiaTexto on PasoGuia {
  String get titulo => switch (this) {
    PasoGuia.google => 'Conecta tu cuenta de Google',
    PasoGuia.carpetas => 'Crea tus carpetas en Drive',
    PasoGuia.sincronizacion => 'Espera a que todo se sincronice',
    PasoGuia.datosFacturacion => 'Completa tus datos de facturación',
    PasoGuia.numeracion => 'Revisa el número de tu próxima factura',
    PasoGuia.cliente => 'Crea tu primer cliente',
    PasoGuia.bolo => 'Crea un bolo para ese cliente',
    PasoGuia.factura => 'Crea su factura',
    PasoGuia.compartir => 'Compártela',
    PasoGuia.facturada => 'Márcala como facturada',
    PasoGuia.cobrada => 'Márcala como cobrada',
    PasoGuia.gasto => 'Añade un gasto o una inversión',
  };

  String get detalle => switch (this) {
    PasoGuia.google =>
      'Para guardar tus facturas en Drive y tus bolos en '
          'Calendar.',
    PasoGuia.carpetas => 'Una carpeta por año, trimestre y mes.',
    PasoGuia.sincronizacion =>
      'Tus datos viajan a la nube para que los veas '
          'en todos tus dispositivos.',
    PasoGuia.datosFacturacion =>
      'Logo, nombre, NIF, dirección e IBAN. El '
          'logo es opcional.',
    PasoGuia.numeracion =>
      'Si ya has facturado este año fuera de MisBolos, '
          'dile por dónde seguir.',
    PasoGuia.cliente => 'Con sus datos fiscales para poder facturarle.',
    PasoGuia.bolo => 'La fecha, el caché y si es facturable.',
    PasoGuia.factura => 'Desde el propio bolo, con un toque.',
    PasoGuia.compartir => 'Por WhatsApp, por correo o como prefieras.',
    PasoGuia.facturada => 'Así sabes qué te deben.',
    PasoGuia.cobrada => 'Y así sabes qué has cobrado.',
    PasoGuia.gasto => 'Lo que te gastas también cuenta para tus impuestos.',
  };
}

/// Si los datos de facturación están lo bastante completos para emitir.
///
/// Nombre, NIF y dirección son los que el PDF necesita sí o sí; el logo es
/// un adorno.
bool datosFiscalesCompletos(AppSettings? settings) {
  if (settings == null) return false;
  return settings.emisorNombre.trim().isNotEmpty &&
      settings.emisorNIF.trim().isNotEmpty &&
      settings.emisorDireccion.trim().isNotEmpty;
}

/// Lo que la app sabe ahora mismo, para decidir qué pasos están hechos.
@immutable
class SenalesGuia {
  final bool googleConectado;
  final bool carpetasCreadas;
  final bool primeraSincronizacionCompleta;

  /// Para enseñar «Sincronizando…» mientras tanto.
  final bool sincronizando;

  final bool datosFacturacionCompletos;

  /// El usuario ha contestado a la pregunta del número de factura.
  final bool numeracionRevisada;

  final bool hayClientes;
  final bool hayBolos;
  final bool hayFacturas;

  /// El usuario ha compartido una factura o la ha mandado por correo.
  final bool facturaCompartida;

  final bool hayFacturaEmitida;
  final bool hayFacturaCobrada;
  final bool hayGastoOInversion;

  /// Pasos que el usuario ha decidido saltarse.
  final Set<PasoGuia> saltados;

  /// En repaso los pasos no se dan por hechos mirando los datos, sino solo
  /// según se completan: cada paso de [pasosRepaso] cuenta como hecho.
  final bool modoRepaso;
  final Set<PasoGuia> pasosRepaso;

  const SenalesGuia({
    this.googleConectado = false,
    this.carpetasCreadas = false,
    this.primeraSincronizacionCompleta = false,
    this.sincronizando = false,
    this.datosFacturacionCompletos = false,
    this.numeracionRevisada = false,
    this.hayClientes = false,
    this.hayBolos = false,
    this.hayFacturas = false,
    this.facturaCompartida = false,
    this.hayFacturaEmitida = false,
    this.hayFacturaCobrada = false,
    this.hayGastoOInversion = false,
    this.saltados = const {},
    this.modoRepaso = false,
    this.pasosRepaso = const {},
  });
}

@immutable
class EstadoPasoGuia {
  final PasoGuia paso;
  final bool hecho;
  final bool saltado;

  /// El paso está en marcha pero aún no ha terminado, como la primera
  /// sincronización.
  final bool enCurso;

  const EstadoPasoGuia(
    this.paso, {
    required this.hecho,
    this.saltado = false,
    this.enCurso = false,
  });

  /// Si ya no hay nada que hacer con él, lo haya hecho o se lo haya saltado.
  bool get cerrado => hecho || saltado;
}

/// Los doce pasos con lo que se sabe de cada uno.
List<EstadoPasoGuia> pasosDeLaGuia(SenalesGuia senales) {
  // En repaso solo cuenta lo que se ha ido completando: los datos que ya
  // había no dan por hecho ningún paso.
  bool hecho(PasoGuia paso) {
    if (senales.modoRepaso) return senales.pasosRepaso.contains(paso);
    return switch (paso) {
      PasoGuia.google => senales.googleConectado,
      PasoGuia.carpetas => senales.carpetasCreadas,
      PasoGuia.sincronizacion => senales.primeraSincronizacionCompleta,
      PasoGuia.datosFacturacion => senales.datosFacturacionCompletos,
      PasoGuia.numeracion => senales.numeracionRevisada,
      PasoGuia.cliente => senales.hayClientes,
      PasoGuia.bolo => senales.hayBolos,
      PasoGuia.factura => senales.hayFacturas,
      PasoGuia.compartir => senales.facturaCompartida,
      PasoGuia.facturada => senales.hayFacturaEmitida,
      PasoGuia.cobrada => senales.hayFacturaCobrada,
      PasoGuia.gasto => senales.hayGastoOInversion,
    };
  }

  return [
    for (final paso in PasoGuia.values)
      EstadoPasoGuia(
        paso,
        hecho: hecho(paso),
        saltado: senales.saltados.contains(paso),
        enCurso:
            paso == PasoGuia.sincronizacion &&
            senales.sincronizando &&
            !hecho(paso),
      ),
  ];
}

/// Cuántos pasos quedan cerrados, que es el número que ve el usuario.
int pasosCerrados(List<EstadoPasoGuia> pasos) =>
    pasos.where((p) => p.cerrado).length;

/// El siguiente paso que le toca al usuario, o null si ya no queda ninguno.
PasoGuia? siguientePaso(List<EstadoPasoGuia> pasos) {
  for (final estado in pasos) {
    if (!estado.cerrado) return estado.paso;
  }
  return null;
}

/// Si ya no queda nada: toca la tarjeta de cierre.
bool guiaTerminada(List<EstadoPasoGuia> pasos) => siguientePaso(pasos) == null;

/// A dónde lleva «Hacerlo ahora» y qué tour se enseña al llegar.
@immutable
class DestinoPaso {
  final String ruta;
  final Tour tour;

  /// Si el elemento que tocaba no existe, se va a la lista con una
  /// explicación en lugar de dejar al usuario tirado.
  final String? aviso;

  const DestinoPaso(this.ruta, this.tour, {this.aviso});
}

/// Qué abre cada paso.
///
/// Los pasos finales van al elemento concreto, no a la lista: al bolo que
/// falta por facturar y a la factura recién hecha. Si ese elemento ya no
/// está, se cae a la lista con un aviso que explica qué hacer.
DestinoPaso destinoDelPaso(
  PasoGuia paso, {
  String? boloSinFacturaId,
  String? facturaRecienteId,
}) {
  switch (paso) {
    case PasoGuia.google:
    case PasoGuia.carpetas:
    case PasoGuia.sincronizacion:
    case PasoGuia.datosFacturacion:
      return const DestinoPaso('/profile', Tour.perfil);
    case PasoGuia.numeracion:
      return const DestinoPaso('/settings', Tour.ajustes);
    case PasoGuia.cliente:
      return const DestinoPaso('/client/new', Tour.nuevoCliente);
    case PasoGuia.bolo:
      return const DestinoPaso('/gig/new', Tour.nuevoBolo);
    case PasoGuia.factura:
      if (boloSinFacturaId == null) {
        return const DestinoPaso(
          '/calendar',
          Tour.agenda,
          aviso:
              'No encuentro el bolo que acabas de crear. Abre uno de la '
              'lista y genera su factura desde ahí.',
        );
      }
      return DestinoPaso('/gig/$boloSinFacturaId', Tour.boloAFacturar);
    case PasoGuia.compartir:
    case PasoGuia.facturada:
    case PasoGuia.cobrada:
      if (facturaRecienteId == null) {
        return DestinoPaso(
          '/finanzas',
          Tour.facturas,
          aviso:
              'No encuentro tu factura. Ábrela desde la lista y sigue '
              'desde ahí.',
        );
      }
      final tour = switch (paso) {
        PasoGuia.compartir => Tour.facturaCompartir,
        PasoGuia.facturada => Tour.facturaEmitir,
        _ => Tour.facturaCobrar,
      };
      return DestinoPaso('/invoice/$facturaRecienteId', tour);
    case PasoGuia.gasto:
      // A la pestaña de Gastos de Finanzas, no al formulario: el tour señala
      // el botón de añadir de esa lista, que es lo que el usuario busca.
      return const DestinoPaso('/finanzas?tab=gastos', Tour.gastos);
  }
}
