import 'package:flutter/material.dart';

/// El fondo de color que asoma al deslizar una tarjeta de una lista.
///
/// Siempre con icono y etiqueta: el color solo no dice qué va a pasar.
class FondoDeslizar extends StatelessWidget {
  final Color color;
  final IconData icono;
  final String etiqueta;

  /// A la izquierda para el gesto que empieza por la izquierda.
  final bool aLaIzquierda;

  /// Debe coincidir con el de la tarjeta para que no se vea descuadrado.
  final EdgeInsets margen;

  /// El de la tarjeta que tiene detrás.
  final double radio;

  const FondoDeslizar({
    super.key,
    required this.color,
    required this.icono,
    required this.etiqueta,
    required this.aLaIzquierda,
    this.margen = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.radio = 14,
  });

  @override
  Widget build(BuildContext context) {
    final sobreColor = Theme.of(context).colorScheme.onPrimary;
    return Container(
      margin: margen,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radio),
      ),
      alignment: aLaIzquierda ? Alignment.centerLeft : Alignment.centerRight,
      padding: EdgeInsets.only(
        left: aLaIzquierda ? 20 : 0,
        right: aLaIzquierda ? 0 : 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: sobreColor, size: 24),
          const SizedBox(height: 4),
          Text(
            etiqueta,
            style: TextStyle(
              color: sobreColor,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
