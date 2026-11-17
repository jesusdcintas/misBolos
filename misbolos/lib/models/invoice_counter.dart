import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'invoice.dart';

/// La serie de una factura, tal y como se ve en su número: F-2026-0016.
String serieDeFactura(InvoiceType tipo) =>
    tipo == InvoiceType.rectifying ? 'R' : 'F';

/// El número que el usuario ha fijado a mano para la siguiente factura.
///
/// Solo guarda eso: emitir o crear facturas no lo toca. Una serie y un año
/// sin contador es lo normal, y significa «sigue contando como siempre».
@immutable
class InvoiceCounter {
  final String serie;
  final int fiscalYear;
  final int nextNumber;

  /// Cuándo se cambió a mano. Es lo que decide quién gana al fusionar.
  final DateTime updatedAt;

  const InvoiceCounter({
    required this.serie,
    required this.fiscalYear,
    required this.nextNumber,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'serie': serie,
    'fiscal_year': fiscalYear,
    'next_number': nextNumber,
    'updated_at': updatedAt.toIso8601String(),
  };

  static InvoiceCounter fromMap(Map<String, Object?> map) => InvoiceCounter(
    serie: map['serie'] as String,
    fiscalYear: (map['fiscal_year'] as num).toInt(),
    nextNumber: (map['next_number'] as num).toInt(),
    updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
  );
}

/// El número tal y como lo ve el usuario: F-2026-0016.
String numeroVisualFactura({
  required String serie,
  required int year,
  required int numero,
}) => '$serie-$year-${numero.toString().padLeft(4, '0')}';

/// El número que le toca a la siguiente factura.
///
/// Es el mayor entre seguir contando y lo que el usuario haya fijado. Así,
/// borrar la última factura libera su número aunque haya un contador fijado,
/// y un contador fijado nunca puede repetir un número ya usado.
int proximoNumeroFactura({required int mayorUsado, int? contadorFijado}) {
  return math.max(mayorUsado + 1, contadorFijado ?? 1);
}

/// Si se puede fijar [numero] cuando la factura más alta de esa serie y año
/// es [mayorUsado].
///
/// Un número ya usado no vale: la numeración no puede repetirse ni retroceder.
bool sePuedeFijarNumero(int numero, {required int mayorUsado}) {
  return numero > 0 && numero > mayorUsado;
}

/// Qué contador vale, el de este dispositivo o el de la nube.
///
/// Gana el cambio más reciente, para que se pueda corregir a la baja un
/// número fijado por error. Que no se repita un número ya usado lo garantiza
/// [proximoNumeroFactura], no esta función.
///
/// Un contador sin fijar (null) nunca pisa a uno fijado.
InvoiceCounter? fusionarContadores(
  InvoiceCounter? local,
  InvoiceCounter? nube,
) {
  if (local == null) return nube;
  if (nube == null) return local;
  return nube.updatedAt.isAfter(local.updatedAt) ? nube : local;
}
