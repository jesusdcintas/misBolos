import 'dart:async';

import 'package:flutter/material.dart';

/// Borrado que se puede deshacer durante unos segundos.
///
/// El elemento desaparece de la lista al momento, pero el borrado de verdad
/// solo se ejecuta cuando se cierra el aviso sin pulsar «Deshacer». Así no hay
/// nada que revertir: si el usuario deshace, no se ha borrado nada.
///
/// Si la pantalla se cierra o la app pasa a segundo plano con un borrado en
/// espera, se ejecuta en ese momento, para no dejarlo a medias.
class BorradoConDeshacer<T> {
  /// Lo que se ejecuta si el aviso se cierra sin deshacer.
  final Future<void> Function(T elemento) alConfirmar;

  /// Se avisa cuando cambia la lista de ocultos, para repintar.
  final VoidCallback? alCambiar;

  /// Cuánto dura el aviso.
  final Duration duracion;

  final Set<Object> _ocultos = {};
  final Map<Object, T> _pendientes = {};

  BorradoConDeshacer({
    required this.alConfirmar,
    this.alCambiar,
    this.duracion = const Duration(seconds: 5),
  });

  /// Si [clave] está esperando a borrarse y por tanto no debe pintarse.
  bool estaOculto(Object clave) => _ocultos.contains(clave);

  /// Filtra de una lista lo que está pendiente de borrar.
  List<E> visibles<E>(List<E> elementos, Object Function(E) clave) =>
      elementos.where((e) => !estaOculto(clave(e))).toList();

  /// Hay algo esperando.
  bool get hayPendientes => _pendientes.isNotEmpty;

  /// Oculta [elemento] y enseña el aviso con «Deshacer».
  Future<void> borrar({
    required BuildContext context,
    required Object clave,
    required T elemento,
    required String mensaje,
  }) async {
    _ocultos.add(clave);
    _pendientes[clave] = elemento;
    alCambiar?.call();

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final cerrado = await messenger
        .showSnackBar(
          SnackBar(
            content: Text(mensaje),
            duration: duracion,
            // Con acción, Flutter deja el aviso fijo por defecto; aquí tiene
            // que cerrarse solo, porque ese cierre es lo que confirma.
            persist: false,
            action: SnackBarAction(
              label: 'Deshacer',
              onPressed: () {
                // El trabajo real se hace al resolverse `closed`.
              },
            ),
          ),
        )
        .closed;

    if (cerrado == SnackBarClosedReason.action) {
      // Deshecho: no se ha tocado nada.
      _ocultos.remove(clave);
      _pendientes.remove(clave);
      alCambiar?.call();
      return;
    }
    await _confirmar(clave);
  }

  /// Ejecuta ya todos los borrados en espera.
  ///
  /// Se llama al cerrar la pantalla y al pasar la app a segundo plano.
  Future<void> confirmarPendientes() async {
    for (final clave in _pendientes.keys.toList()) {
      await _confirmar(clave);
    }
  }

  Future<void> _confirmar(Object clave) async {
    final elemento = _pendientes.remove(clave);
    if (elemento == null) return;
    await alConfirmar(elemento);
    _ocultos.remove(clave);
    alCambiar?.call();
  }
}
