import '../../models/app_settings.dart';

/// Combina los ajustes descargados de la nube con los que ya hay en local.
///
/// Parte de [cloud] y conserva los campos que `user_settings` no guarda, para
/// que una descarga no los devuelva a los valores por defecto del constructor
/// de [AppSettings]. Los textos del emisor se conservan solo si la nube los
/// trae vacíos y en local hay algo.
AppSettings mergeDownloadedSettings(AppSettings local, AppSettings cloud) {
  String keepLocalIfCloudEmpty(String localValue, String cloudValue) {
    if (cloudValue.trim().isEmpty && localValue.trim().isNotEmpty) {
      return localValue;
    }
    return cloudValue;
  }

  return cloud.copyWith(
    logoPath: keepLocalIfCloudEmpty(local.logoPath, cloud.logoPath),
    logoSize: local.logoSize,
    pdfTheme: local.pdfTheme,
    emisorNombre: keepLocalIfCloudEmpty(
      local.emisorNombre,
      cloud.emisorNombre,
    ),
    emisorNIF: keepLocalIfCloudEmpty(local.emisorNIF, cloud.emisorNIF),
    emisorDireccion: keepLocalIfCloudEmpty(
      local.emisorDireccion,
      cloud.emisorDireccion,
    ),
    emisorCiudad: keepLocalIfCloudEmpty(
      local.emisorCiudad,
      cloud.emisorCiudad,
    ),
    emisorProvincia: keepLocalIfCloudEmpty(
      local.emisorProvincia,
      cloud.emisorProvincia,
    ),
    emisorCodigoPostal: keepLocalIfCloudEmpty(
      local.emisorCodigoPostal,
      cloud.emisorCodigoPostal,
    ),
    emisorEmail: keepLocalIfCloudEmpty(local.emisorEmail, cloud.emisorEmail),
    emisorTelefono: keepLocalIfCloudEmpty(
      local.emisorTelefono,
      cloud.emisorTelefono,
    ),
    iban: keepLocalIfCloudEmpty(local.iban, cloud.iban),
    notificacionesActivas: local.notificacionesActivas,
    diasRecordatorio: local.diasRecordatorio,
    // La nube no guarda irpf_default: es un ajuste local. Si no se
    // conserva aquí, cada descarga lo devuelve al 0.15 del constructor.
    irpfDefault: local.irpfDefault,
    driveConnected: local.driveConnected,
    driveAccountEmail: local.driveAccountEmail,
    driveAccountName: local.driveAccountName,
    driveRootFolderId: local.driveRootFolderId,
    driveRootFolderName: local.driveRootFolderName,
    lastDriveBackupAt: local.lastDriveBackupAt,
    lastDriveSyncAt: local.lastDriveSyncAt,
    lastCloudSyncAt: local.lastCloudSyncAt,
    cloudSettingsSignature: local.cloudSettingsSignature,
    // Tampoco se suben a la nube: sin conservarlos, cada descarga los
    // devolvía a los valores por defecto del constructor.
    autoCloudSyncEnabled: local.autoCloudSyncEnabled,
    autoCloudSyncIntervalSeconds: local.autoCloudSyncIntervalSeconds,
    appThemeMode: local.appThemeMode,
    securityPinEnabled: local.securityPinEnabled,
    securityPinCode: local.securityPinCode,
    securityBiometricEnabled: local.securityBiometricEnabled,
    securityLockDelaySeconds: local.securityLockDelaySeconds,
  );
}
