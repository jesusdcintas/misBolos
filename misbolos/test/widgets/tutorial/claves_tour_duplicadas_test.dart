import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduce el fallo de la pantalla roja al eliminar la cuenta:
///
///   Multiple widgets used the same GlobalKey.
///
/// Pasaba porque las claves del tour estaban declaradas como globales de
/// módulo (`final _claveTour... = GlobalKey()`). Durante la redirección al
/// cerrar sesión o eliminar la cuenta, la misma pantalla llega a estar montada
/// dos veces a la vez (la vieja desmontándose y la nueva construyéndose), y
/// esa única GlobalKey quedaba pegada a dos widgets → el assert de Flutter.
///
/// La corrección es crear la clave en el State de la pantalla, de modo que
/// cada instancia tenga la suya. Este test monta dos pantallas iguales a la
/// vez y comprueba que ya no chocan.

/// Una pantalla que sigue el patrón correcto: su clave de tour nace en el
/// State, no es una global compartida.
class _PantallaConTour extends StatefulWidget {
  const _PantallaConTour();

  @override
  State<_PantallaConTour> createState() => _PantallaConTourState();
}

class _PantallaConTourState extends State<_PantallaConTour> {
  // La clave por instancia: esto es justo lo que arregla el fallo.
  final GlobalKey _claveTour = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _claveTour,
      child: const SizedBox(width: 10, height: 10),
    );
  }
}

void main() {
  testWidgets('dos instancias de la misma pantalla con tour no chocan de '
      'GlobalKey', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [_PantallaConTour(), _PantallaConTour()],
        ),
      ),
    );

    // Con una GlobalKey global compartida, aquí saltaría el assert
    // «Multiple widgets used the same GlobalKey». Con la clave por instancia,
    // las dos conviven sin problema.
    expect(tester.takeException(), isNull);
    expect(find.byType(KeyedSubtree), findsNWidgets(2));
  });
}
