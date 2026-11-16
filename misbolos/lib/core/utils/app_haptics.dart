import '../services/hapticos.dart';

/// Nombres antiguos de las vibraciones.
///
/// Se mantienen para no tocar los sitios que ya los usaban, pero delegan en
/// [Hapticos] para que el interruptor de Ajustes también los apague.
class AppHaptics {
  AppHaptics._();

  static void light() => Hapticos.toque();
  static void medium() => Hapticos.umbral();
  static void heavy() => Hapticos.umbral();
  static void select() => Hapticos.seleccion();
  static void error() => Hapticos.error();
}
