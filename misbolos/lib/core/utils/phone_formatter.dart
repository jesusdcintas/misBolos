class PhoneFormatter {
  static String? toWhatsAppNumber(String? rawPhone) {
    if (rawPhone == null) return null;
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty) return null;

    var normalized = trimmed.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.startsWith('00')) {
      normalized = normalized.substring(2);
    } else if (normalized.startsWith('+')) {
      normalized = normalized.substring(1);
    }

    // Regla práctica local: si viene un móvil nacional de 9 dígitos,
    // asumimos prefijo España (+34).
    if (normalized.length == 9) {
      normalized = '34$normalized';
    }

    if (!RegExp(r'^[0-9]{10,15}$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }
}
