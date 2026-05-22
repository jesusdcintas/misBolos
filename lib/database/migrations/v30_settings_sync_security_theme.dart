const String v30SettingsSyncSecurityTheme = '''
ALTER TABLE app_settings ADD COLUMN auto_cloud_sync_enabled INTEGER NOT NULL DEFAULT 1;
ALTER TABLE app_settings ADD COLUMN auto_cloud_sync_interval_seconds INTEGER NOT NULL DEFAULT 45;
ALTER TABLE app_settings ADD COLUMN app_theme_mode TEXT NOT NULL DEFAULT 'light';
ALTER TABLE app_settings ADD COLUMN security_pin_enabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE app_settings ADD COLUMN security_pin_code TEXT NOT NULL DEFAULT '';
ALTER TABLE app_settings ADD COLUMN security_biometric_enabled INTEGER NOT NULL DEFAULT 0;
''';
