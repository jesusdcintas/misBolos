import 'package:pdf/pdf.dart';

enum PdfTheme {
  clasico('Clásico', 'Azul oscuro profesional'),
  moderno('Moderno', 'Negro y gris'),
  corporativo('Corporativo', 'Azul brillante'),
  elegante('Elegante', 'Morado sofisticado'),
  natural('Natural', 'Verde sereno'),
  calido('Cálido', 'Tonos tierra');

  final String label;
  final String description;

  const PdfTheme(this.label, this.description);

  PdfColor get primaryColor {
    switch (this) {
      case PdfTheme.clasico:
        return const PdfColor.fromInt(0xFF1B2A4A);
      case PdfTheme.moderno:
        return const PdfColor.fromInt(0xFF2D2D2D);
      case PdfTheme.corporativo:
        return const PdfColor.fromInt(0xFF0066CC);
      case PdfTheme.elegante:
        return const PdfColor.fromInt(0xFF6B4C9A);
      case PdfTheme.natural:
        return const PdfColor.fromInt(0xFF2E7D32);
      case PdfTheme.calido:
        return const PdfColor.fromInt(0xFF8B4513);
    }
  }

  PdfColor get headerBg => primaryColor;

  PdfColor get rowAlt {
    switch (this) {
      case PdfTheme.clasico:
        return const PdfColor.fromInt(0xFFF5F6FA);
      case PdfTheme.moderno:
        return const PdfColor.fromInt(0xFFF0F0F0);
      case PdfTheme.corporativo:
        return const PdfColor.fromInt(0xFFE6F0FA);
      case PdfTheme.elegante:
        return const PdfColor.fromInt(0xFFF3EFF8);
      case PdfTheme.natural:
        return const PdfColor.fromInt(0xFFE8F5E9);
      case PdfTheme.calido:
        return const PdfColor.fromInt(0xFFFFF8E1);
    }
  }

  PdfColor get accentColor {
    switch (this) {
      case PdfTheme.clasico:
        return const PdfColor.fromInt(0xFF3D5A80);
      case PdfTheme.moderno:
        return const PdfColor.fromInt(0xFF505050);
      case PdfTheme.corporativo:
        return const PdfColor.fromInt(0xFF0088FF);
      case PdfTheme.elegante:
        return const PdfColor.fromInt(0xFF9575CD);
      case PdfTheme.natural:
        return const PdfColor.fromInt(0xFF4CAF50);
      case PdfTheme.calido:
        return const PdfColor.fromInt(0xFFD4A574);
    }
  }

  static PdfTheme fromName(String? name) {
    if (name == null) return PdfTheme.clasico;
    return PdfTheme.values.firstWhere(
      (t) => t.name == name,
      orElse: () => PdfTheme.clasico,
    );
  }
}
