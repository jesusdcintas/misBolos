/// v13: añade campos de IVA a assets para separar correctamente la base
/// imponible amortizable del IVA deducible en el trimestre de compra.
///
/// - importe_con_iva: lo que pagó realmente el usuario (con IVA)
/// - iva_rate:        porcentaje de IVA aplicado (21, 10, 4 ó 0)
/// - iva_amount:      IVA = importe_con_iva - importe_total (base imponible)
///
/// El campo importe_total existente pasa a representar la BASE IMPONIBLE.
/// Para registros anteriores se deja a 0 (se detecta en el formulario).
const String v13AssetsIva = '''
ALTER TABLE assets ADD COLUMN importe_con_iva REAL NOT NULL DEFAULT 0.0;
ALTER TABLE assets ADD COLUMN iva_rate REAL NOT NULL DEFAULT 21.0;
ALTER TABLE assets ADD COLUMN iva_amount REAL NOT NULL DEFAULT 0.0
''';
