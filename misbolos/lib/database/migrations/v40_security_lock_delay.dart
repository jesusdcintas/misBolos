const String v40SecurityLockDelay = '''
ALTER TABLE app_settings ADD COLUMN security_lock_delay_seconds INTEGER NOT NULL DEFAULT 5;
''';
