/// Constantes fiscales de la retención de IRPF que se aplica a cada factura.
///
/// No tiene nada que ver con el pago fraccionado trimestral (modelo 130), que
/// es un 20 % fijo y vive en `FinancialSummaryService.irpfPagoFraccionadoRate`.
class RetencionIrpf {
  RetencionIrpf._();

  /// Tipo general: facturas a empresas y profesionales.
  static const double general = 0.15;

  /// Tipo reducido: nuevos autónomos y artistas con ingresos bajos.
  static const double reducida = 0.07;

  /// Sin retención.
  static const double ninguna = 0.0;

  /// Opciones válidas, en el orden en que se muestran.
  static const List<double> opciones = [ninguna, reducida, general];

  /// Etiqueta corta del tipo, por ejemplo `15%`.
  static String etiqueta(double rate) => '${(rate * 100).toStringAsFixed(0)}%';

  /// Explicación de cuándo corresponde cada tipo. Null si no es una opción.
  static String? explicacion(double rate) {
    switch (rate) {
      case general:
        return 'General. Facturas a empresas y profesionales (salas, '
            'promotoras, agencias).';
      case reducida:
        return 'Nuevos autónomos (año de alta y dos siguientes) o artistas '
            'con ingresos del año anterior inferiores a 15.000 €.';
      case ninguna:
        return 'Facturas a particulares, clientes extranjeros o actividad '
            'empresarial (por ejemplo, organización de eventos).';
      default:
        return null;
    }
  }

  /// Aviso común a todas las opciones.
  static const String notaGeneral =
      'No es el pago trimestral del IRPF, que es siempre del 20 %. Consulta '
      'con tu gestoría qué tipo te corresponde.';

  /// Indica si [rate] es una de las opciones válidas.
  static bool esValida(double rate) => opciones.contains(rate);
}
