import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Colores que no se adaptan al tema y por tanto no valen para fondos ni
/// textos: en modo oscuro quedan ilegibles.
final _prohibidos = RegExp(
  r'AppColors\.(textPrimary|textSecondary|primaryLight|warningBg|errorBg|'
  r'successBg)\b|Colors\.(white|black)\b',
);

/// Ficheros donde el color fijo es correcto, con el motivo.
///
/// La clave es la ruta relativa a `lib/`.
const _excepciones = <String, String>{
  // Definen los propios temas: aquí es donde se decide el valor de cada token.
  'core/theme/app_theme.dart': 'define los temas claro y oscuro',
  'core/theme/app_theme_colors.dart': 'define los tokens de color',

  // Superficies que son oscuras o de color fijo en los dos temas, así que el
  // texto blanco encima es correcto siempre.
  'widgets/dashboard/income_period_card.dart':
      'tarjeta azul marino fija a propósito',
  'widgets/common/status_badge.dart': 'etiqueta sobre un fondo de color fijo',
  'widgets/common/facturable_badge.dart':
      'etiqueta sobre un fondo de color fijo',
  'widgets/common/animated_facturable_toggle.dart':
      'interruptor sobre un fondo de color fijo',
  'widgets/common/expandable_fab.dart':
      'iconos sobre botones flotantes de color fijo',
  'widgets/common/cobrado_confetti_button.dart':
      'icono sobre un botón de color fijo',
  'widgets/common/serpentina_celebration.dart': 'confeti decorativo',
  'widgets/common/loading_overlay.dart': 'velo oscuro sobre la pantalla',
  'widgets/common/misbolos_app_bar.dart':
      'barra azul marino fija en los dos temas',
  'app.dart': 'icono sobre la burbuja de Bolin, con degradado fijo',

  // Representan papel impreso, que siempre es blanco.
  'services/pdf_service.dart': 'genera el PDF, que va sobre papel blanco',
  'screens/settings/settings_screen.dart':
      'maqueta del PDF impreso: papel blanco',
};

/// Pantallas que aún no se han migrado al tema.
///
/// No son excepciones: son trabajo pendiente. La lista solo evita que el test
/// falle por algo que ya se sabe, y debe ir vaciándose.
const _pendientes = <String>{
  // La pantalla del asistente está oculta tras el flag de IA.
  'screens/ai/ai_assistant_screen.dart',
};

void main() {
  test('ninguna pantalla migrada usa colores que no se adaptan al tema', () {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'el test se ejecuta desde la raíz del proyecto Flutter',
    );

    final fallos = <String>[];
    for (final fichero in lib.listSync(recursive: true).whereType<File>()) {
      if (!fichero.path.endsWith('.dart')) continue;
      final rel = fichero.path.replaceFirst('lib/', '');
      if (_excepciones.containsKey(rel) || _pendientes.contains(rel)) continue;

      final lineas = fichero.readAsLinesSync();
      for (var i = 0; i < lineas.length; i++) {
        final linea = lineas[i];
        if (!_prohibidos.hasMatch(linea)) continue;
        // Un color fijo dentro de una rama de isDark sí se adapta. La guarda
        // puede estar justo encima o justo debajo, según cómo parta la línea
        // el formateador.
        final contexto = lineas
            .sublist(
              (i - 4).clamp(0, i),
              (i + 4).clamp(0, lineas.length),
            )
            .join('\n');
        if (contexto.contains('isDark') || contexto.contains('brightness')) {
          continue;
        }
        fallos.add('$rel:${i + 1}  ${linea.trim()}');
      }
    }

    expect(
      fallos,
      isEmpty,
      reason:
          'usa context.colors o colorScheme en vez de un color fijo:\n'
          '${fallos.join('\n')}',
    );
  });

  test('las excepciones y los pendientes no se solapan', () {
    for (final rel in _pendientes) {
      expect(
        _excepciones.containsKey(rel),
        isFalse,
        reason: '$rel está a la vez como excepción y como pendiente',
      );
    }
  });

  test('cada excepción lleva su motivo', () {
    for (final entrada in _excepciones.entries) {
      expect(
        entrada.value.trim(),
        isNotEmpty,
        reason: 'la excepción ${entrada.key} no explica por qué',
      );
    }
  });
}
