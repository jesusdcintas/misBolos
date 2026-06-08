-- =============================================================
-- MisBolos - Schema SQL para Supabase
-- Multi-usuario: cada DJ solo ve sus propios datos.
-- Se sincronizan clientes, bolos oficiales, bolos en B, facturas,
-- gastos e inversiones.
-- =============================================================

-- Tabla de clientes
CREATE TABLE IF NOT EXISTS clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  alias TEXT DEFAULT '',
  aliases JSONB DEFAULT '[]'::jsonb,
  cif_nif TEXT,
  direccion TEXT,
  ciudad TEXT,
  provincia TEXT,
  codigo_postal TEXT,
  email TEXT,
  telefono TEXT,
  whatsapp_phone TEXT,
  notas TEXT,
  number_locked BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tabla de bolos (facturables y en B)
CREATE TABLE IF NOT EXISTS gigs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
  fecha DATE NOT NULL,
  notas TEXT,
  cachet REAL,
  facturable BOOLEAN NOT NULL DEFAULT TRUE,
  status TEXT NOT NULL DEFAULT 'confirmado'
    CHECK (status IN (
      'confirmado',
      'facturado',
      'cobrado',
      'confirmado_b',
      'realizado_b',
      'cobrado_b',
      'cancelado',
    )),
  invoice_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- Tabla de facturas
CREATE TABLE IF NOT EXISTS invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  numero TEXT NOT NULL,
  gig_id UUID REFERENCES gigs(id) ON DELETE SET NULL,
  client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
  fecha_emision DATE NOT NULL,
  subtotal REAL NOT NULL DEFAULT 0,
  iva_porcentaje REAL NOT NULL DEFAULT 21,
  iva_importe REAL NOT NULL DEFAULT 0,
  irpf_porcentaje REAL NOT NULL DEFAULT 0,
  irpf_importe REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0,
  items JSONB NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'borrador'
    CHECK (status IN ('borrador', 'enviada', 'pagada')),
  is_fiscally_issued BOOLEAN NOT NULL DEFAULT false,
  fiscal_hash TEXT,
  fiscal_record_id UUID,
  invoice_type TEXT NOT NULL DEFAULT 'normal'
    CHECK (invoice_type IN ('normal', 'rectifying')),
  rectifies_invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,
  rectification_reason TEXT,
  rectification_reason_type TEXT,
  rectification_reason_description TEXT,
  rectification_type TEXT
    CHECK (rectification_type IS NULL OR rectification_type IN ('substitution', 'difference')),
  original_invoice_number TEXT,
  original_invoice_date DATE,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- FK circular: gigs.invoice_id → invoices (se añade después de crear ambas tablas)
ALTER TABLE gigs
  ADD CONSTRAINT fk_gigs_invoice
  FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL;

-- El número de factura es único por usuario y año fiscal, no global
CREATE UNIQUE INDEX idx_invoices_year_type_numero
  ON invoices(user_id, (EXTRACT(YEAR FROM fecha_emision)), invoice_type, numero)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS invoice_number_changes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  old_number INTEGER,
  new_number INTEGER NOT NULL CHECK (new_number > 0),
  source TEXT NOT NULL CHECK (source IN ('create_invoice', 'manual_renumber')),
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índices
CREATE INDEX idx_clients_user_id ON clients(user_id);
CREATE INDEX idx_gigs_user_id ON gigs(user_id);
CREATE INDEX idx_gigs_fecha ON gigs(fecha);
CREATE INDEX idx_gigs_client_id ON gigs(client_id);
CREATE INDEX idx_gigs_status ON gigs(status);
CREATE INDEX idx_invoices_user_id ON invoices(user_id);
CREATE INDEX idx_invoices_client_id ON invoices(client_id);
CREATE INDEX idx_invoices_status ON invoices(status);

-- Row Level Security (RLS)
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE gigs ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

-- Políticas: cada usuario solo accede a SUS datos
CREATE POLICY "Users can view their own clients"
  ON clients FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own clients"
  ON clients FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own clients"
  ON clients FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own clients"
  ON clients FOR DELETE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own gigs"
  ON gigs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own gigs"
  ON gigs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own gigs"
  ON gigs FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own gigs"
  ON gigs FOR DELETE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own invoices"
  ON invoices FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own invoices"
  ON invoices FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own invoices"
  ON invoices FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own invoices"
  ON invoices FOR DELETE
  USING (auth.uid() = user_id);

-- Función para auto-asignar user_id y actualizar updated_at
CREATE OR REPLACE FUNCTION set_user_id()
RETURNS TRIGGER AS $$
BEGIN
  NEW.user_id = auth.uid();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers auto-asignación de user_id al insertar
CREATE TRIGGER clients_set_user_id
  BEFORE INSERT ON clients
  FOR EACH ROW EXECUTE FUNCTION set_user_id();

CREATE TRIGGER gigs_set_user_id
  BEFORE INSERT ON gigs
  FOR EACH ROW EXECUTE FUNCTION set_user_id();

CREATE TRIGGER invoices_set_user_id
  BEFORE INSERT ON invoices
  FOR EACH ROW EXECUTE FUNCTION set_user_id();

-- Triggers updated_at
CREATE TRIGGER clients_updated_at
  BEFORE UPDATE ON clients
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER gigs_updated_at
  BEFORE UPDATE ON gigs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER invoices_updated_at
  BEFORE UPDATE ON invoices
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================
-- Tabla de configuración del usuario (datos de facturación)
-- =============================================================
CREATE TABLE IF NOT EXISTS user_settings (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  emisor_nombre TEXT,
  emisor_nif TEXT,
  emisor_direccion TEXT,
  emisor_ciudad TEXT,
  emisor_provincia TEXT,
  emisor_codigo_postal TEXT,
  emisor_email TEXT,
  emisor_telefono TEXT,
  iban TEXT,
  iva_default REAL DEFAULT 0.21,
  in_app_invoice_reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  email_invoice_reminders_enabled BOOLEAN NOT NULL DEFAULT false,
  invoice_reminder_frequency TEXT NOT NULL DEFAULT 'weekly',
  invoice_last_reminder_sent_at TIMESTAMPTZ,
  last_invoice_reminder_email_sent_at TIMESTAMPTZ,
  verifactu_enabled BOOLEAN NOT NULL DEFAULT false,
  logo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own settings"
  ON user_settings FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own settings"
  ON user_settings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own settings"
  ON user_settings FOR UPDATE
  USING (auth.uid() = user_id);

CREATE TRIGGER user_settings_updated_at
  BEFORE UPDATE ON user_settings
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE IF NOT EXISTS invoice_reminder_email_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_email TEXT NOT NULL,
  subject TEXT NOT NULL,
  invoice_ids TEXT[] NOT NULL DEFAULT '{}',
  invoice_count INTEGER NOT NULL DEFAULT 0,
  total_pending NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'sent',
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS invoice_fiscal_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  record_type TEXT NOT NULL CHECK (record_type IN ('issue', 'rectification', 'cancellation')),
  invoice_number TEXT NOT NULL,
  invoice_series TEXT NOT NULL DEFAULT '',
  issued_at TIMESTAMPTZ NOT NULL,
  previous_hash TEXT,
  current_hash TEXT NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  aeat_status TEXT NOT NULL DEFAULT 'not_sent'
    CHECK (aeat_status IN ('not_sent', 'pending', 'sent', 'accepted', 'rejected', 'error')),
  aeat_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoice_reminder_email_logs_user_created
  ON invoice_reminder_email_logs(user_id, created_at DESC);

ALTER TABLE invoice_reminder_email_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own invoice reminder email logs"
  ON invoice_reminder_email_logs FOR SELECT USING (auth.uid() = user_id);

-- =============================================================
-- Tabla de gastos (expenses) — módulo v10
-- =============================================================
CREATE TABLE IF NOT EXISTS expenses (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fecha      DATE NOT NULL,
  concepto   TEXT NOT NULL,
  proveedor  TEXT,
  importe_base        REAL NOT NULL,
  iva_rate            REAL NOT NULL DEFAULT 21.0,
  iva_amount          REAL NOT NULL,
  total               REAL NOT NULL,
  categoria           TEXT NOT NULL DEFAULT 'otros',
  es_deducible        BOOLEAN NOT NULL DEFAULT TRUE,
  porcentaje_deduccion REAL NOT NULL DEFAULT 100.0,
  documento_path      TEXT,
  notas               TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_expenses_user_id ON expenses(user_id);
CREATE INDEX idx_expenses_fecha   ON expenses(fecha);

ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own expenses"
  ON expenses FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own expenses"
  ON expenses FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own expenses"
  ON expenses FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own expenses"
  ON expenses FOR DELETE USING (auth.uid() = user_id);

CREATE TRIGGER expenses_set_user_id
  BEFORE INSERT ON expenses
  FOR EACH ROW EXECUTE FUNCTION set_user_id();

CREATE TRIGGER expenses_updated_at
  BEFORE UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================
-- Tabla de inversiones/inmovilizado (assets) — módulo v11
-- =============================================================
CREATE TABLE IF NOT EXISTS assets (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  descripcion         TEXT NOT NULL,
  fecha_compra        DATE NOT NULL,
  importe_total       REAL NOT NULL,
  importe_con_iva     REAL NOT NULL DEFAULT 0.0,
  iva_rate            REAL NOT NULL DEFAULT 21.0,
  iva_amount          REAL NOT NULL DEFAULT 0.0,
  valor_residual      REAL NOT NULL DEFAULT 0.0,
  vida_util_anos      INTEGER NOT NULL,
  metodo_amortizacion TEXT NOT NULL DEFAULT 'lineal',
  categoria           TEXT NOT NULL DEFAULT 'otros',
  documento_path      TEXT,
  notas               TEXT,
  activo              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_assets_user_id ON assets(user_id);
CREATE INDEX idx_assets_activo  ON assets(activo);

ALTER TABLE assets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own assets"
  ON assets FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own assets"
  ON assets FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own assets"
  ON assets FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own assets"
  ON assets FOR DELETE USING (auth.uid() = user_id);

CREATE TRIGGER assets_set_user_id
  BEFORE INSERT ON assets
  FOR EACH ROW EXECUTE FUNCTION set_user_id();

CREATE TRIGGER assets_updated_at
  BEFORE UPDATE ON assets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =============================================================
-- Tabla de eventos de aplicación (trazabilidad futura)
-- =============================================================
CREATE TABLE IF NOT EXISTS app_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_app_events_user_id ON app_events(user_id);
CREATE INDEX idx_app_events_entity ON app_events(entity_type, entity_id);
CREATE INDEX idx_app_events_created_at ON app_events(created_at);

ALTER TABLE app_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own app events"
  ON app_events FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own app events"
  ON app_events FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE TRIGGER app_events_set_user_id
  BEFORE INSERT ON app_events
  FOR EACH ROW EXECUTE FUNCTION set_user_id();

-- =============================================================
-- Logs de envío de facturas por email
-- =============================================================
CREATE TABLE IF NOT EXISTS invoice_email_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invoice_id UUID REFERENCES invoices(id) ON DELETE CASCADE,
  client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
  recipient_email TEXT NOT NULL,
  provider TEXT NOT NULL,
  subject TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'sent', 'failed')),
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_invoice_email_logs_user_id ON invoice_email_logs(user_id);
CREATE INDEX idx_invoice_email_logs_invoice ON invoice_email_logs(invoice_id);
CREATE INDEX idx_invoice_email_logs_created_at
  ON invoice_email_logs(created_at);

ALTER TABLE invoice_email_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own invoice email logs"
  ON invoice_email_logs FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own invoice email logs"
  ON invoice_email_logs FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own invoice email logs"
  ON invoice_email_logs FOR UPDATE USING (auth.uid() = user_id);

CREATE TRIGGER invoice_email_logs_set_user_id
  BEFORE INSERT ON invoice_email_logs
  FOR EACH ROW EXECUTE FUNCTION set_user_id();
