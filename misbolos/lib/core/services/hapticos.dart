import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clave del interruptor de vibración. Solo local, no se sincroniza.
const String hapticosActivadosKey = 'hapticos_activados';

/// Vibraciones de la app.
///
/// Un único punto de entrada para que el interruptor de Ajustes las apague
/// todas. En escritorio y web no hace nada: solo iOS y Android tienen motor
/// háptico al que merezca la pena hablarle.
class Hapticos {
  Hapticos._();

  static bool _activados = true;

  /// Si el usuario los tiene encendidos.
  static bool get activados => _activados;

  /// Solo hay vibración en móvil.
  static bool get disponibles =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Lee la preferencia guardada. Se llama una vez al arrancar.
  static Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _activados = prefs.getBool(hapticosActivadosKey) ?? true;
  }

  /// Cambia la preferencia y la guarda.
  static Future<void> cambiar(bool valor) async {
    _activados = valor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(hapticosActivadosKey, valor);
  }

  /// Solo para los tests.
  @visibleForTesting
  static void fijarActivadosEnTests(bool valor) => _activados = valor;

  static bool get _puede => _activados && disponibles;

  /// Elegir una opción de un grupo. El toque más suave.
  static void seleccion() {
    if (!_puede) return;
    HapticFeedback.selectionClick();
  }

  /// Botones principales e interruptores.
  static void toque() {
    if (!_puede) return;
    HapticFeedback.lightImpact();
  }

  /// Un deslizamiento llega al punto en que se ejecuta la acción.
  static void umbral() {
    if (!_puede) return;
    HapticFeedback.mediumImpact();
  }

  /// Una acción importante sale bien.
  ///
  /// iOS tiene un patrón propio para esto, pero Flutter no lo expone. Se imita
  /// encadenando dos impactos de menos a más, que es como suena el de iOS.
  static void exito() {
    if (!_puede) return;
    HapticFeedback.lightImpact();
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (_puede) HapticFeedback.mediumImpact();
    });
  }

  /// Falla una validación al guardar.
  ///
  /// Dos golpes iguales y seguidos, que se leen como un «no». Mejor que el
  /// HapticFeedback.vibrate de antes, que en Android era un zumbido largo.
  static void error() {
    if (!_puede) return;
    HapticFeedback.mediumImpact();
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (_puede) HapticFeedback.mediumImpact();
    });
  }
}
