class AppSettings {
  final String logoPath;
  final double logoSize;
  final String pdfTheme;
  final String emisorNombre;
  final String emisorNIF;
  final String emisorDireccion;
  final String emisorCiudad;
  final String emisorProvincia;
  final String emisorCodigoPostal;
  final String emisorEmail;
  final String emisorTelefono;
  final String iban;
  final double ivaDefault;
  final bool notificacionesActivas;
  final int diasRecordatorio;

  AppSettings({
    this.logoPath = '',
    this.logoSize = 180,
    this.pdfTheme = 'moderno',
    this.emisorNombre = '',
    this.emisorNIF = '',
    this.emisorDireccion = '',
    this.emisorCiudad = '',
    this.emisorProvincia = '',
    this.emisorCodigoPostal = '',
    this.emisorEmail = '',
    this.emisorTelefono = '',
    this.iban = '',
    this.ivaDefault = 0.21,
    this.notificacionesActivas = true,
    this.diasRecordatorio = 7,
  });

  AppSettings copyWith({
    String? logoPath,
    double? logoSize,
    String? pdfTheme,
    String? emisorNombre,
    String? emisorNIF,
    String? emisorDireccion,
    String? emisorCiudad,
    String? emisorProvincia,
    String? emisorCodigoPostal,
    String? emisorEmail,
    String? emisorTelefono,
    String? iban,
    double? ivaDefault,
    bool? notificacionesActivas,
    int? diasRecordatorio,
  }) {
    return AppSettings(
      logoPath: logoPath ?? this.logoPath,
      logoSize: logoSize ?? this.logoSize,
      pdfTheme: pdfTheme ?? this.pdfTheme,
      emisorNombre: emisorNombre ?? this.emisorNombre,
      emisorNIF: emisorNIF ?? this.emisorNIF,
      emisorDireccion: emisorDireccion ?? this.emisorDireccion,
      emisorCiudad: emisorCiudad ?? this.emisorCiudad,
      emisorProvincia: emisorProvincia ?? this.emisorProvincia,
      emisorCodigoPostal: emisorCodigoPostal ?? this.emisorCodigoPostal,
      emisorEmail: emisorEmail ?? this.emisorEmail,
      emisorTelefono: emisorTelefono ?? this.emisorTelefono,
      iban: iban ?? this.iban,
      ivaDefault: ivaDefault ?? this.ivaDefault,
      notificacionesActivas: notificacionesActivas ?? this.notificacionesActivas,
      diasRecordatorio: diasRecordatorio ?? this.diasRecordatorio,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'logo_path': logoPath,
      'logo_size': logoSize,
      'pdf_theme': pdfTheme,
      'emisor_nombre': emisorNombre,
      'emisor_nif': emisorNIF,
      'emisor_direccion': emisorDireccion,
      'emisor_ciudad': emisorCiudad,
      'emisor_provincia': emisorProvincia,
      'emisor_codigo_postal': emisorCodigoPostal,
      'emisor_email': emisorEmail,
      'emisor_telefono': emisorTelefono,
      'iban': iban,
      'iva_default': ivaDefault,
      'notificaciones_activas': notificacionesActivas ? 1 : 0,
      'dias_recordatorio': diasRecordatorio,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      logoPath: map['logo_path'] as String? ?? '',
      logoSize: (map['logo_size'] as num?)?.toDouble() ?? 80,
      pdfTheme: map['pdf_theme'] as String? ?? 'clasico',
      emisorNombre: map['emisor_nombre'] as String? ?? '',
      emisorNIF: map['emisor_nif'] as String? ?? '',
      emisorDireccion: map['emisor_direccion'] as String? ?? '',
      emisorCiudad: map['emisor_ciudad'] as String? ?? '',
      emisorProvincia: map['emisor_provincia'] as String? ?? '',
      emisorCodigoPostal: map['emisor_codigo_postal'] as String? ?? '',
      emisorEmail: map['emisor_email'] as String? ?? '',
      emisorTelefono: map['emisor_telefono'] as String? ?? '',
      iban: map['iban'] as String? ?? '',
      ivaDefault: (map['iva_default'] as num?)?.toDouble() ?? 0.21,
      notificacionesActivas: (map['notificaciones_activas'] as int?) == 1,
      diasRecordatorio: map['dias_recordatorio'] as int? ?? 7,
    );
  }
}
