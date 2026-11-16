import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../models/invoice.dart';
import 'fondo_deslizar.dart';

/// Deslizar una factura hacia la derecha para marcarla como cobrada.
///
/// Solo en las pendientes de cobro: un borrador no se cobra y una cobrada no
/// se vuelve a cobrar, así que ahí la tarjeta ni siquiera se deja deslizar.
class DeslizarParaCobrar extends StatelessWidget {
  final Invoice invoice;
  final Widget child;

  /// Se llama al cruzar el punto. Quien lo use enseña el aviso con
  /// «Deshacer»: aquí no se espera a nada, para que la tarjeta vuelva ya.
  final VoidCallback alCobrar;

  const DeslizarParaCobrar({
    super.key,
    required this.invoice,
    required this.child,
    required this.alCobrar,
  });

  /// Si [invoice] está en un estado en el que cobrarla tiene sentido.
  static bool sePuedeCobrar(Invoice invoice) =>
      invoice.status == InvoiceStatus.enviada;

  @override
  Widget build(BuildContext context) {
    if (!sePuedeCobrar(invoice)) return child;

    return Dismissible(
      key: ValueKey('cobrar-${invoice.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        alCobrar();
        // La factura no se va de la lista: cambia de estado y sigue ahí.
        return false;
      },
      background: FondoDeslizar(
        color: context.colors.success,
        icono: Icons.check_circle,
        etiqueta: 'Cobrada',
        aLaIzquierda: true,
      ),
      child: child,
    );
  }
}
