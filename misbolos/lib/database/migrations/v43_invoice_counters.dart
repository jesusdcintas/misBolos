/// El número que el usuario fija a mano para la siguiente factura.
///
/// Solo guarda lo que se fija a mano: emitir o crear facturas no lo toca. El
/// número siguiente sale de combinar este valor con el mayor número ya usado,
/// así que borrar la última factura libera su número aunque haya contador.
const String v43InvoiceCounters = '''
CREATE TABLE IF NOT EXISTS invoice_counters (
  serie TEXT NOT NULL,
  fiscal_year INTEGER NOT NULL,
  next_number INTEGER NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (serie, fiscal_year)
);
''';
