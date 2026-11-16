import 'package:flutter/material.dart';

/// Pregunta si descartar los cambios sin guardar.
///
/// Devuelve true si el usuario quiere salir perdiéndolos.
Future<bool> confirmarDescartar(BuildContext context) async {
  final respuesta = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Descartar los cambios?'),
      content: const Text('Lo que has escrito se perderá.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Seguir editando'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Descartar'),
        ),
      ],
    ),
  );
  return respuesta ?? false;
}

/// Envuelve un formulario para que no se salga de él sin querer.
///
/// Con [hayCambios] en false sale directamente, sin preguntar: es el caso de
/// un formulario que no se ha tocado y el de uno que acaba de guardarse.
class FormularioConCambios extends StatelessWidget {
  final bool hayCambios;
  final Widget child;

  const FormularioConCambios({
    super.key,
    required this.hayCambios,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hayCambios,
      onPopInvokedWithResult: (seSalio, _) async {
        if (seSalio) return;
        final navigator = Navigator.of(context);
        if (await confirmarDescartar(context)) {
          navigator.pop();
        }
      },
      child: child,
    );
  }
}
