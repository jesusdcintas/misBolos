-- =============================================================
-- MisBolos - Schema SQL para Supabase
-- Multi-usuario: cada DJ solo ve sus propios datos.
-- Solo se sincronizan datos "facturables" (oficiales).
-- Los datos "en B" NUNCA salen del dispositivo.
-- =============================================================

-- Tabla de clientes
CREATE TABLE IF NOT EXISTS clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre TEXT NOT NULL,
  alias TEXT DEFAULT '',
  aliases JSONB DEFAULT '[]'::jsonb,
  email TEXT,
  telefono TEXT,
  direccion TEXT,
  nif_cif TEXT,
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Tabla de bolos (solo facturables se sincronizan)
CREATE TABLE IF NOT EXISTS gigs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
  fecha DATE NOT NULL,
  lugar TEXT,
  cache REAL NOT NULL DEFAULT 0,
  notas TEXT,
  facturable BOOLEAN NOT NULL DEFAULT TRUE CHECK (facturable = TRUE),
  status TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (status IN ('pendiente', 'factura_generada', 'factura_enviada', 'pagado', 'cancelado')),
  invoice_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
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
  total REAL NOT NULL DEFAULT 0,
  items JSONB NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'borrador'
    CHECK (status IN ('borrador', 'enviada', 'pagada')),
  notas TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- FK circular: gigs.invoice_id → invoices (se añade después de crear ambas tablas)
ALTER TABLE gigs
  ADD CONSTRAINT fk_gigs_invoice
  FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL;

-- El número de factura es único por usuario, no global
CREATE UNIQUE INDEX idx_invoices_numero_user ON invoices(user_id, numero);

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
