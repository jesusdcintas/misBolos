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
  final double irpfDefault;
  final bool notificacionesActivas;
  final int diasRecordatorio;
  final bool emailInvoiceRemindersEnabled;
  final String invoiceReminderFrequency;
  final DateTime? invoiceLastReminderSentAt;
  final bool verifactuEnabled;
  final String? driveRootFolderId;
  final String? driveRootFolderName;
  final String? driveAccountEmail;
  final String? driveAccountName;
  final bool driveConnected;
  final DateTime? lastDriveBackupAt;
  final DateTime? lastDriveSyncAt;
  final DateTime? lastCloudSyncAt;
  final String? cloudSettingsSignature;
  final bool autoCloudSyncEnabled;
  final int autoCloudSyncIntervalSeconds;
  final String appThemeMode;
  final bool securityPinEnabled;
  final String securityPinCode;
  final bool securityBiometricEnabled;

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
    this.irpfDefault = 0.15,
    this.notificacionesActivas = true,
    this.diasRecordatorio = 7,
    this.emailInvoiceRemindersEnabled = false,
    this.invoiceReminderFrequency = 'weekly',
    this.invoiceLastReminderSentAt,
    this.verifactuEnabled = false,
    this.driveRootFolderId,
    this.driveRootFolderName,
    this.driveAccountEmail,
    this.driveAccountName,
    this.driveConnected = false,
    this.lastDriveBackupAt,
    this.lastDriveSyncAt,
    this.lastCloudSyncAt,
    this.cloudSettingsSignature,
    this.autoCloudSyncEnabled = true,
    this.autoCloudSyncIntervalSeconds = 45,
    this.appThemeMode = 'light',
    this.securityPinEnabled = false,
    this.securityPinCode = '',
    this.securityBiometricEnabled = false,
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
    double? irpfDefault,
    bool? notificacionesActivas,
    int? diasRecordatorio,
    bool? emailInvoiceRemindersEnabled,
    String? invoiceReminderFrequency,
    DateTime? invoiceLastReminderSentAt,
    bool? verifactuEnabled,
    String? driveRootFolderId,
    String? driveRootFolderName,
    String? driveAccountEmail,
    String? driveAccountName,
    bool? driveConnected,
    DateTime? lastDriveBackupAt,
    DateTime? lastDriveSyncAt,
    DateTime? lastCloudSyncAt,
    String? cloudSettingsSignature,
    bool? autoCloudSyncEnabled,
    int? autoCloudSyncIntervalSeconds,
    String? appThemeMode,
    bool? securityPinEnabled,
    String? securityPinCode,
    bool? securityBiometricEnabled,
    bool clearDriveRootFolder = false,
    bool clearDriveAccount = false,
    bool clearLastDriveBackupAt = false,
    bool clearLastDriveSyncAt = false,
    bool clearInvoiceLastReminderSentAt = false,
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
      irpfDefault: irpfDefault ?? this.irpfDefault,
      notificacionesActivas:
          notificacionesActivas ?? this.notificacionesActivas,
      diasRecordatorio: diasRecordatorio ?? this.diasRecordatorio,
      emailInvoiceRemindersEnabled:
          emailInvoiceRemindersEnabled ?? this.emailInvoiceRemindersEnabled,
      invoiceReminderFrequency:
          invoiceReminderFrequency ?? this.invoiceReminderFrequency,
      invoiceLastReminderSentAt: clearInvoiceLastReminderSentAt
          ? null
          : invoiceLastReminderSentAt ?? this.invoiceLastReminderSentAt,
      verifactuEnabled: verifactuEnabled ?? this.verifactuEnabled,
      driveRootFolderId: clearDriveRootFolder
          ? null
          : driveRootFolderId ?? this.driveRootFolderId,
      driveRootFolderName: clearDriveRootFolder
          ? null
          : driveRootFolderName ?? this.driveRootFolderName,
      driveAccountEmail: clearDriveAccount
          ? null
          : driveAccountEmail ?? this.driveAccountEmail,
      driveAccountName: clearDriveAccount
          ? null
          : driveAccountName ?? this.driveAccountName,
      driveConnected: driveConnected ?? this.driveConnected,
      lastDriveBackupAt: clearLastDriveBackupAt
          ? null
          : lastDriveBackupAt ?? this.lastDriveBackupAt,
      lastDriveSyncAt: clearLastDriveSyncAt
          ? null
          : lastDriveSyncAt ?? this.lastDriveSyncAt,
      lastCloudSyncAt: lastCloudSyncAt ?? this.lastCloudSyncAt,
      cloudSettingsSignature:
          cloudSettingsSignature ?? this.cloudSettingsSignature,
      autoCloudSyncEnabled: autoCloudSyncEnabled ?? this.autoCloudSyncEnabled,
      autoCloudSyncIntervalSeconds:
          autoCloudSyncIntervalSeconds ?? this.autoCloudSyncIntervalSeconds,
      appThemeMode: appThemeMode ?? this.appThemeMode,
      securityPinEnabled: securityPinEnabled ?? this.securityPinEnabled,
      securityPinCode: securityPinCode ?? this.securityPinCode,
      securityBiometricEnabled:
          securityBiometricEnabled ?? this.securityBiometricEnabled,
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
      'irpf_default': irpfDefault,
      'notificaciones_activas': notificacionesActivas ? 1 : 0,
      'dias_recordatorio': diasRecordatorio,
      'email_invoice_reminders_enabled': emailInvoiceRemindersEnabled ? 1 : 0,
      'invoice_reminder_frequency': invoiceReminderFrequency,
      'invoice_last_reminder_sent_at': invoiceLastReminderSentAt
          ?.toIso8601String(),
      'last_invoice_reminder_email_sent_at': invoiceLastReminderSentAt
          ?.toIso8601String(),
      'verifactu_enabled': verifactuEnabled ? 1 : 0,
      'drive_root_folder_id': driveRootFolderId,
      'drive_root_folder_name': driveRootFolderName,
      'drive_account_email': driveAccountEmail,
      'drive_account_name': driveAccountName,
      'drive_connected': driveConnected ? 1 : 0,
      'last_drive_backup_at': lastDriveBackupAt?.toIso8601String(),
      'last_drive_sync_at': lastDriveSyncAt?.toIso8601String(),
      'last_cloud_sync_at': lastCloudSyncAt?.toIso8601String(),
      'cloud_settings_signature': cloudSettingsSignature,
      'auto_cloud_sync_enabled': autoCloudSyncEnabled ? 1 : 0,
      'auto_cloud_sync_interval_seconds': autoCloudSyncIntervalSeconds,
      'app_theme_mode': appThemeMode,
      'security_pin_enabled': securityPinEnabled ? 1 : 0,
      'security_pin_code': securityPinCode,
      'security_biometric_enabled': securityBiometricEnabled ? 1 : 0,
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
      irpfDefault: (map['irpf_default'] as num?)?.toDouble() ?? 0.15,
      notificacionesActivas: (map['notificaciones_activas'] as int?) == 1,
      diasRecordatorio: map['dias_recordatorio'] as int? ?? 7,
      emailInvoiceRemindersEnabled:
          (map['email_invoice_reminders_enabled'] as int? ?? 0) == 1,
      invoiceReminderFrequency:
          map['invoice_reminder_frequency'] as String? ?? 'weekly',
      invoiceLastReminderSentAt: map['invoice_last_reminder_sent_at'] != null
          ? DateTime.tryParse(map['invoice_last_reminder_sent_at'] as String)
          : map['last_invoice_reminder_email_sent_at'] != null
          ? DateTime.tryParse(
              map['last_invoice_reminder_email_sent_at'] as String,
            )
          : null,
      verifactuEnabled: (map['verifactu_enabled'] as int? ?? 0) == 1,
      driveRootFolderId: map['drive_root_folder_id'] as String?,
      driveRootFolderName: map['drive_root_folder_name'] as String?,
      driveAccountEmail: map['drive_account_email'] as String?,
      driveAccountName: map['drive_account_name'] as String?,
      driveConnected: (map['drive_connected'] as int? ?? 0) == 1,
      lastDriveBackupAt: map['last_drive_backup_at'] != null
          ? DateTime.tryParse(map['last_drive_backup_at'] as String)
          : null,
      lastDriveSyncAt: map['last_drive_sync_at'] != null
          ? DateTime.tryParse(map['last_drive_sync_at'] as String)
          : null,
      lastCloudSyncAt: map['last_cloud_sync_at'] != null
          ? DateTime.tryParse(map['last_cloud_sync_at'] as String)
          : null,
      cloudSettingsSignature: map['cloud_settings_signature'] as String?,
      autoCloudSyncEnabled: (map['auto_cloud_sync_enabled'] as int? ?? 1) == 1,
      autoCloudSyncIntervalSeconds:
          map['auto_cloud_sync_interval_seconds'] as int? ?? 45,
      appThemeMode: map['app_theme_mode'] as String? ?? 'light',
      securityPinEnabled: (map['security_pin_enabled'] as int? ?? 0) == 1,
      securityPinCode: map['security_pin_code'] as String? ?? '',
      securityBiometricEnabled:
          (map['security_biometric_enabled'] as int? ?? 0) == 1,
    );
  }

  @Deprecated('Use invoiceLastReminderSentAt')
  DateTime? get lastInvoiceReminderEmailSentAt => invoiceLastReminderSentAt;
}
