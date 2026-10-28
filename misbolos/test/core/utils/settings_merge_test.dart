import 'package:flutter_test/flutter_test.dart';
import 'package:misbolos/core/utils/settings_merge.dart';
import 'package:misbolos/models/app_settings.dart';

/// Ajustes locales con un valor distinto del por defecto en cada campo que la
/// nube no guarda, para detectar si la descarga pisa alguno.
AppSettings _localConTodoCambiado() => AppSettings(
  logoPath: '/local/logo.png',
  logoSize: 240,
  pdfTheme: 'clasico',
  irpfDefault: 0.0,
  notificacionesActivas: false,
  diasRecordatorio: 3,
  driveConnected: true,
  driveAccountEmail: 'dj@example.com',
  driveAccountName: 'DJ Local',
  driveRootFolderId: 'carpeta-123',
  driveRootFolderName: 'MisBolos',
  lastDriveBackupAt: DateTime(2026, 10, 1),
  lastDriveSyncAt: DateTime(2026, 10, 2),
  lastCloudSyncAt: DateTime(2026, 10, 3),
  cloudSettingsSignature: 'firma-local',
  autoCloudSyncEnabled: false,
  autoCloudSyncIntervalSeconds: 300,
  appThemeMode: 'dark',
  securityPinEnabled: true,
  securityPinCode: '1234',
  securityBiometricEnabled: true,
  securityLockDelaySeconds: 60,
);

/// Lo que devuelve `downloadSettings`: solo trae los campos de `user_settings`,
/// y el resto queda con los valores por defecto del constructor.
AppSettings _nubeComoLaDevuelveSupabase() => AppSettings(
  emisorNombre: 'DJ Nube',
  emisorNIF: 'B00000000',
  emisorDireccion: 'Calle Nube 1',
  emisorCiudad: 'Sevilla',
  emisorProvincia: 'Sevilla',
  emisorCodigoPostal: '41001',
  emisorEmail: 'nube@example.com',
  emisorTelefono: '600000000',
  iban: 'ES0000000000000000000000',
  ivaDefault: 0.10,
  notificacionesActivas: true,
  emailInvoiceRemindersEnabled: true,
  invoiceReminderFrequency: 'daily',
  invoiceLastReminderSentAt: DateTime(2026, 9, 9),
  verifactuEnabled: true,
);

void main() {
  group('mergeDownloadedSettings: campos que solo existen en local', () {
    test('la retención del 0 % sobrevive a una descarga', () {
      final merged = mergeDownloadedSettings(
        _localConTodoCambiado(),
        _nubeComoLaDevuelveSupabase(),
      );
      expect(merged.irpfDefault, 0.0);
    });

    test('los ajustes de sincronización y tema sobreviven', () {
      final merged = mergeDownloadedSettings(
        _localConTodoCambiado(),
        _nubeComoLaDevuelveSupabase(),
      );
      expect(merged.autoCloudSyncEnabled, isFalse);
      expect(merged.autoCloudSyncIntervalSeconds, 300);
      expect(merged.appThemeMode, 'dark');
    });

    test('sobreviven los 21 campos que la nube no guarda', () {
      final local = _localConTodoCambiado();
      final merged = mergeDownloadedSettings(
        local,
        _nubeComoLaDevuelveSupabase(),
      );

      expect(merged.logoSize, local.logoSize);
      expect(merged.pdfTheme, local.pdfTheme);
      expect(merged.irpfDefault, local.irpfDefault);
      expect(merged.notificacionesActivas, local.notificacionesActivas);
      expect(merged.diasRecordatorio, local.diasRecordatorio);
      expect(merged.driveConnected, local.driveConnected);
      expect(merged.driveAccountEmail, local.driveAccountEmail);
      expect(merged.driveAccountName, local.driveAccountName);
      expect(merged.driveRootFolderId, local.driveRootFolderId);
      expect(merged.driveRootFolderName, local.driveRootFolderName);
      expect(merged.lastDriveBackupAt, local.lastDriveBackupAt);
      expect(merged.lastDriveSyncAt, local.lastDriveSyncAt);
      expect(merged.lastCloudSyncAt, local.lastCloudSyncAt);
      expect(merged.cloudSettingsSignature, local.cloudSettingsSignature);
      expect(merged.autoCloudSyncEnabled, local.autoCloudSyncEnabled);
      expect(
        merged.autoCloudSyncIntervalSeconds,
        local.autoCloudSyncIntervalSeconds,
      );
      expect(merged.appThemeMode, local.appThemeMode);
      expect(merged.securityPinEnabled, local.securityPinEnabled);
      expect(merged.securityPinCode, local.securityPinCode);
      expect(merged.securityBiometricEnabled, local.securityBiometricEnabled);
      expect(merged.securityLockDelaySeconds, local.securityLockDelaySeconds);
    });

    test('no se pierden aunque local sea todo por defecto', () {
      final local = AppSettings();
      final merged = mergeDownloadedSettings(
        local,
        _nubeComoLaDevuelveSupabase(),
      );
      expect(merged.irpfDefault, 0.15);
      expect(merged.appThemeMode, 'light');
      expect(merged.autoCloudSyncIntervalSeconds, 45);
    });
  });

  group('mergeDownloadedSettings: campos que manda la nube', () {
    test('la nube gana en los campos que sí guarda', () {
      final merged = mergeDownloadedSettings(
        _localConTodoCambiado(),
        _nubeComoLaDevuelveSupabase(),
      );
      expect(merged.ivaDefault, 0.10);
      expect(merged.emailInvoiceRemindersEnabled, isTrue);
      expect(merged.invoiceReminderFrequency, 'daily');
      expect(merged.invoiceLastReminderSentAt, DateTime(2026, 9, 9));
      expect(merged.verifactuEnabled, isTrue);
    });

    test('los datos del emisor de la nube pisan los locales', () {
      final merged = mergeDownloadedSettings(
        _localConTodoCambiado(),
        _nubeComoLaDevuelveSupabase(),
      );
      expect(merged.emisorNombre, 'DJ Nube');
      expect(merged.emisorNIF, 'B00000000');
      expect(merged.iban, 'ES0000000000000000000000');
    });
  });

  group('mergeDownloadedSettings: textos vacíos en la nube', () {
    test('se conserva el valor local si la nube lo trae vacío', () {
      final merged = mergeDownloadedSettings(
        AppSettings(
          emisorNombre: 'DJ Local',
          iban: 'ES1111111111111111111111',
          logoPath: '/local/logo.png',
        ),
        AppSettings(),
      );
      expect(merged.emisorNombre, 'DJ Local');
      expect(merged.iban, 'ES1111111111111111111111');
      expect(merged.logoPath, '/local/logo.png');
    });

    test('un valor local en blanco no se conserva frente a la nube vacía', () {
      final merged = mergeDownloadedSettings(
        AppSettings(emisorNombre: '   '),
        AppSettings(),
      );
      expect(merged.emisorNombre, '');
    });

    test('la nube con contenido gana aunque local tenga algo', () {
      final merged = mergeDownloadedSettings(
        AppSettings(emisorCiudad: 'Cádiz'),
        AppSettings(emisorCiudad: 'Sevilla'),
      );
      expect(merged.emisorCiudad, 'Sevilla');
    });
  });
}
