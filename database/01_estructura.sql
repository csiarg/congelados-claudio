-- ============================================================
-- CONGELADOS CLAUDIO · Base de datos v2
-- 01_estructura.sql  →  Tablas, índices y triggers básicos
-- Ejecutar en Supabase > SQL Editor (instalación nueva, una sola vez)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm  WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- ------------------------------------------------------------
-- Trigger genérico: mantiene updated_at
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tg_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- ============================================================
-- CONFIGURACIÓN GENERAL (una sola fila)
-- ============================================================
CREATE TABLE configuracion (
  id                       INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  nombre_empresa           TEXT NOT NULL DEFAULT 'Congelados Claudio',
  permitir_stock_negativo  BOOLEAN NOT NULL DEFAULT false,
  whatsapp_numero          TEXT,
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO configuracion (id) VALUES (1);

-- ============================================================
-- CAMIONES
-- ============================================================
CREATE TABLE camiones (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero           TEXT NOT NULL UNIQUE,              -- "C-01"
  patente          TEXT UNIQUE,
  descripcion      TEXT,                              -- "Ford Transit blanca"
  chofer_nombre    TEXT,
  chofer_telefono  TEXT,
  activo           BOOLEAN NOT NULL DEFAULT true,
  observaciones    TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_camiones_upd BEFORE UPDATE ON camiones
  FOR EACH ROW EXECUTE FUNCTION tg_updated_at();

-- ============================================================
-- USUARIOS DEL SISTEMA (perfil + rol)  · 1 a 1 con auth.users
-- ============================================================
CREATE TABLE perfiles (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT,
  nombre      TEXT,
  rol         TEXT NOT NULL DEFAULT 'consulta'
              CHECK (rol IN ('admin','operario','consulta')),
  camion_id   UUID REFERENCES camiones(id) ON DELETE SET NULL,  -- camión habitual del operario
  activo      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_perfiles_upd BEFORE UPDATE ON perfiles
  FOR EACH ROW EXECUTE FUNCTION tg_updated_at();

-- Al crear un usuario en Supabase Auth se crea su perfil.
-- El PRIMER usuario queda como admin; el resto entra como 'consulta'.
CREATE OR REPLACE FUNCTION public.tg_nuevo_usuario()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.perfiles (user_id, email, nombre, rol)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'nombre', split_part(NEW.email, '@', 1)),
    CASE WHEN EXISTS (SELECT 1 FROM public.perfiles) THEN 'consulta' ELSE 'admin' END
  )
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nuevo_usuario ON auth.users;
CREATE TRIGGER trg_nuevo_usuario AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.tg_nuevo_usuario();

-- ============================================================
-- PROVEEDORES
-- ============================================================
CREATE TABLE proveedores (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre      TEXT NOT NULL UNIQUE,
  cuit        TEXT,
  telefono    TEXT,
  email       TEXT,
  activo      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_proveedores_upd BEFORE UPDATE ON proveedores
  FOR EACH ROW EXECUTE FUNCTION tg_updated_at();

-- ============================================================
-- PRODUCTOS
-- ============================================================
CREATE TABLE productos (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo             TEXT NOT NULL UNIQUE,                 -- SKU / código interno
  descripcion        TEXT NOT NULL,
  marca              TEXT,
  rubro              TEXT,                                 -- Pollo, Rebozados, Helados...
  proveedor_id       UUID REFERENCES proveedores(id) ON DELETE SET NULL,
  unidad             TEXT NOT NULL DEFAULT 'unidad'
                     CHECK (unidad IN ('unidad','kg','caja','bulto')),
  costo_promedio     NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (costo_promedio >= 0),
  costo_ultimo       NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (costo_ultimo >= 0),
  margen_porcentaje  NUMERIC(6,2),   -- si está cargado, el precio se recalcula al comprar
  precio_venta       NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (precio_venta >= 0),  -- precio de lista base
  stock_minimo       NUMERIC(12,3) NOT NULL DEFAULT 0,
  destacado          BOOLEAN NOT NULL DEFAULT false,
  activo             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_productos_desc_trgm ON productos USING GIN (descripcion extensions.gin_trgm_ops);
CREATE INDEX idx_productos_proveedor ON productos (proveedor_id);
CREATE INDEX idx_productos_rubro     ON productos (rubro);
CREATE TRIGGER trg_productos_upd BEFORE UPDATE ON productos
  FOR EACH ROW EXECUTE FUNCTION tg_updated_at();

-- Historial de precios de venta (lo llena un trigger, ver más abajo)
CREATE TABLE precios_historico (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  producto_id      UUID NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  precio_anterior  NUMERIC(14,2) NOT NULL,
  precio_nuevo     NUMERIC(14,2) NOT NULL,
  costo_promedio   NUMERIC(14,2),
  variacion_pct    NUMERIC(8,2),
  motivo           TEXT,
  usuario_id       UUID,
  fecha            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_precios_hist_prod ON precios_historico (producto_id, fecha DESC);

-- Cada cambio de precio_venta (por pantalla, importación o función) queda registrado.
-- El motivo se puede pasar con: SELECT set_config('app.motivo_precio', 'Aumento proveedor', true);
CREATE OR REPLACE FUNCTION public.tg_log_precio()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.precio_venta IS DISTINCT FROM OLD.precio_venta THEN
    INSERT INTO precios_historico (producto_id, precio_anterior, precio_nuevo, costo_promedio,
                                   variacion_pct, motivo, usuario_id)
    VALUES (NEW.id, OLD.precio_venta, NEW.precio_venta, NEW.costo_promedio,
            CASE WHEN OLD.precio_venta > 0
                 THEN round((NEW.precio_venta / OLD.precio_venta - 1) * 100, 2) END,
            COALESCE(NULLIF(current_setting('app.motivo_precio', true), ''), 'Ajuste manual'),
            auth.uid());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_productos_precio AFTER UPDATE OF precio_venta ON productos
  FOR EACH ROW EXECUTE FUNCTION tg_log_precio();

-- ============================================================
-- LISTAS DE PRECIOS
-- ajuste_porcentaje: -10 = 10% de descuento sobre precio base, +5 = recargo
-- ============================================================
CREATE TABLE listas_precios (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre             TEXT NOT NULL UNIQUE,
  descripcion        TEXT,
  ajuste_porcentaje  NUMERIC(6,2) NOT NULL DEFAULT 0 CHECK (ajuste_porcentaje > -100),
  activo             BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_listas_upd BEFORE UPDATE ON listas_precios
  FOR EACH ROW EXECUTE FUNCTION tg_updated_at();

-- Precio especial de un producto dentro de una lista (pisa el % de la lista)
CREATE TABLE listas_precios_items (
  lista_id     UUID NOT NULL REFERENCES listas_precios(id) ON DELETE CASCADE,
  producto_id  UUID NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  precio       NUMERIC(14,2) NOT NULL CHECK (precio >= 0),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (lista_id, producto_id)
);

-- ============================================================
-- CLIENTES
-- ============================================================
CREATE TABLE clientes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo           INT GENERATED BY DEFAULT AS IDENTITY UNIQUE,  -- nº de cliente
  nombre           TEXT NOT NULL,                     -- nombre de fantasía
  razon_social     TEXT,
  cuit             TEXT,
  direccion        TEXT,
  localidad        TEXT,
  telefono         TEXT,
  whatsapp         TEXT UNIQUE,     -- solo dígitos, ej 5491122334455 (se normaliza solo)
  email            TEXT,
  lista_precio_id  UUID REFERENCES listas_precios(id) ON DELETE SET NULL,
  camion_id        UUID REFERENCES camiones(id) ON DELETE SET NULL,  -- reparto habitual
  condicion_pago   TEXT NOT NULL DEFAULT 'contado'
                   CHECK (condicion_pago IN ('contado','cta_cte')),
  limite_credito   NUMERIC(14,2) NOT NULL DEFAULT 0,  -- 0 = sin límite
  activo           BOOLEAN NOT NULL DEFAULT true,
  observaciones    TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_clientes_nombre_trgm ON clientes USING GIN (nombre extensions.gin_trgm_ops);
CREATE INDEX idx_clientes_camion ON clientes (camion_id);
CREATE TRIGGER trg_clientes_upd BEFORE UPDATE ON clientes
  FOR EACH ROW EXECUTE FUNCTION tg_updated_at();

-- Normaliza el WhatsApp a solo dígitos con prefijo 549 (Argentina) para poder
-- reconocer al cliente cuando escribe.
CREATE OR REPLACE FUNCTION public.normalizar_whatsapp(p TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d TEXT := regexp_replace(COALESCE(p, ''), '\D', '', 'g');
BEGIN
  IF d = '' THEN RETURN NULL; END IF;
  IF d LIKE '549%' THEN RETURN d; END IF;
  IF d LIKE '54%'  THEN RETURN '549' || substr(d, 3); END IF;
  IF d LIKE '0%'   THEN d := substr(d, 2); END IF;
  -- quita el 15 de celulares escritos "11 15 2233 4455" (área de 2 a 4 dígitos)
  d := regexp_replace(d, '^(\d{2,4})15(\d{6,8})$', '\1\2');
  RETURN '549' || d;
END $$;

CREATE OR REPLACE FUNCTION public.tg_clientes_norm()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.whatsapp := normalizar_whatsapp(NEW.whatsapp);
  RETURN NEW;
END $$;
CREATE TRIGGER trg_clientes_norm BEFORE INSERT OR UPDATE OF whatsapp ON clientes
  FOR EACH ROW EXECUTE FUNCTION tg_clientes_norm();

-- ============================================================
-- RECORRIDOS (jornada de un camión: carga → ventas → descarga)
-- ============================================================
CREATE TABLE recorridos (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero        INT GENERATED ALWAYS AS IDENTITY UNIQUE,
  camion_id     UUID NOT NULL REFERENCES camiones(id),
  fecha         DATE NOT NULL DEFAULT (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,
  estado        TEXT NOT NULL DEFAULT 'en_curso' CHECK (estado IN ('en_curso','cerrado')),
  chofer_nombre TEXT,
  abierto_por   UUID,
  abierto_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  cerrado_por   UUID,
  cerrado_at    TIMESTAMPTZ,
  resumen       JSONB,          -- totales al cierre
  observaciones TEXT
);
-- Un solo recorrido abierto por camión
CREATE UNIQUE INDEX uq_recorrido_abierto ON recorridos (camion_id) WHERE estado = 'en_curso';
CREATE INDEX idx_recorridos_fecha ON recorridos (fecha);

-- ============================================================
-- STOCK
-- camion_id NULL = DEPÓSITO ; camion_id = stock arriba de ese camión
-- Solo se modifica a través de las funciones (nunca a mano).
-- ============================================================
CREATE TABLE stock (
  producto_id  UUID NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  camion_id    UUID REFERENCES camiones(id) ON DELETE CASCADE,
  cantidad     NUMERIC(12,3) NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_stock UNIQUE NULLS NOT DISTINCT (producto_id, camion_id)
);
CREATE INDEX idx_stock_camion ON stock (camion_id);

-- Kardex: cada entrada/salida de mercadería
CREATE TABLE movimientos_stock (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  fecha         TIMESTAMPTZ NOT NULL DEFAULT now(),
  producto_id   UUID NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
  camion_id     UUID REFERENCES camiones(id) ON DELETE SET NULL,   -- NULL = depósito
  tipo          TEXT NOT NULL CHECK (tipo IN (
                  'compra','carga_camion','descarga_camion','venta',
                  'devolucion','cancelacion','ajuste','merma')),
  cantidad      NUMERIC(12,3) NOT NULL,     -- + entra a la ubicación, - sale
  saldo         NUMERIC(12,3) NOT NULL,     -- stock de la ubicación después del movimiento
  costo_unitario NUMERIC(14,2),
  recorrido_id  UUID REFERENCES recorridos(id) ON DELETE SET NULL,
  pedido_id     UUID,
  compra_id     UUID,
  devolucion_id UUID,
  observacion   TEXT,
  usuario_id    UUID
);
CREATE INDEX idx_mov_stock_prod  ON movimientos_stock (producto_id, fecha DESC);
CREATE INDEX idx_mov_stock_cam   ON movimientos_stock (camion_id, fecha DESC);
CREATE INDEX idx_mov_stock_rec   ON movimientos_stock (recorrido_id);

-- ============================================================
-- COMPRAS A PROVEEDORES (ingresan al depósito y actualizan el costo)
-- ============================================================
CREATE TABLE compras (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero           INT GENERATED ALWAYS AS IDENTITY UNIQUE,
  proveedor_id     UUID REFERENCES proveedores(id),
  fecha            DATE NOT NULL DEFAULT (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,
  comprobante      TEXT,     -- nº de factura/remito del proveedor
  total            NUMERIC(14,2) NOT NULL DEFAULT 0,
  observaciones    TEXT,
  usuario_id       UUID,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE compras_items (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  compra_id       UUID NOT NULL REFERENCES compras(id) ON DELETE CASCADE,
  producto_id     UUID NOT NULL REFERENCES productos(id),
  cantidad        NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),
  costo_unitario  NUMERIC(14,2) NOT NULL CHECK (costo_unitario >= 0),
  costo_promedio_resultante NUMERIC(14,2),
  importe         NUMERIC(14,2) NOT NULL
);
CREATE INDEX idx_compras_items_compra ON compras_items (compra_id);

-- ============================================================
-- PEDIDOS / VENTAS
-- ============================================================
CREATE TABLE pedidos (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero           INT GENERATED ALWAYS AS IDENTITY UNIQUE,
  cliente_id       UUID NOT NULL REFERENCES clientes(id),
  fecha            TIMESTAMPTZ NOT NULL DEFAULT now(),
  estado           TEXT NOT NULL DEFAULT 'pendiente'
                   CHECK (estado IN ('pendiente','entregado','cancelado')),
  origen           TEXT NOT NULL DEFAULT 'app'
                   CHECK (origen IN ('app','whatsapp','telefono','mostrador')),
  camion_id        UUID REFERENCES camiones(id),     -- de dónde salió la mercadería (NULL = depósito)
  recorrido_id     UUID REFERENCES recorridos(id),
  reparto_camion_id UUID REFERENCES camiones(id),    -- camión que lo entrega (pedidos del depósito)
  lista_precio_id  UUID REFERENCES listas_precios(id),
  total            NUMERIC(14,2) NOT NULL DEFAULT 0,
  costo_total      NUMERIC(14,2) NOT NULL DEFAULT 0,
  notas            TEXT,
  whatsapp_origen  TEXT,
  usuario_id       UUID,
  entregado_at     TIMESTAMPTZ,
  cancelado_at     TIMESTAMPTZ,
  motivo_cancelacion TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_pedidos_cliente ON pedidos (cliente_id, fecha DESC);
CREATE INDEX idx_pedidos_fecha   ON pedidos (fecha DESC);
CREATE INDEX idx_pedidos_estado  ON pedidos (estado);
CREATE INDEX idx_pedidos_camion  ON pedidos (camion_id);
CREATE INDEX idx_pedidos_reparto ON pedidos (reparto_camion_id) WHERE estado = 'pendiente';

CREATE TABLE pedidos_items (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id        UUID NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
  producto_id      UUID NOT NULL REFERENCES productos(id),
  cantidad         NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),
  precio_unitario  NUMERIC(14,2) NOT NULL,
  costo_unitario   NUMERIC(14,2) NOT NULL DEFAULT 0,
  importe          NUMERIC(14,2) NOT NULL,
  cantidad_devuelta NUMERIC(12,3) NOT NULL DEFAULT 0
);
CREATE INDEX idx_pedidos_items_pedido ON pedidos_items (pedido_id);
CREATE INDEX idx_pedidos_items_prod   ON pedidos_items (producto_id);

-- ============================================================
-- DEVOLUCIONES
-- ============================================================
CREATE TABLE devoluciones (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero        INT GENERATED ALWAYS AS IDENTITY UNIQUE,
  pedido_id     UUID NOT NULL REFERENCES pedidos(id),
  cliente_id    UUID NOT NULL REFERENCES clientes(id),
  camion_id     UUID REFERENCES camiones(id),   -- a dónde vuelve la mercadería (NULL = depósito)
  fecha         TIMESTAMPTZ NOT NULL DEFAULT now(),
  total         NUMERIC(14,2) NOT NULL DEFAULT 0,
  motivo        TEXT,
  vuelve_a_stock BOOLEAN NOT NULL DEFAULT true, -- false = se descarta (merma)
  usuario_id    UUID
);
CREATE TABLE devoluciones_items (
  id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  devolucion_id    UUID NOT NULL REFERENCES devoluciones(id) ON DELETE CASCADE,
  pedido_item_id   BIGINT NOT NULL REFERENCES pedidos_items(id),
  producto_id      UUID NOT NULL REFERENCES productos(id),
  cantidad         NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),
  precio_unitario  NUMERIC(14,2) NOT NULL,
  importe          NUMERIC(14,2) NOT NULL
);

-- ============================================================
-- COBRANZAS
-- ============================================================
CREATE TABLE pagos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero       INT GENERATED ALWAYS AS IDENTITY UNIQUE,
  cliente_id   UUID NOT NULL REFERENCES clientes(id),
  fecha        TIMESTAMPTZ NOT NULL DEFAULT now(),
  monto        NUMERIC(14,2) NOT NULL CHECK (monto > 0),
  medio        TEXT NOT NULL DEFAULT 'efectivo'
               CHECK (medio IN ('efectivo','transferencia','mercadopago','cheque','otro')),
  referencia   TEXT,
  camion_id    UUID REFERENCES camiones(id),   -- si cobró el chofer
  recorrido_id UUID REFERENCES recorridos(id),
  pedido_id    UUID REFERENCES pedidos(id),
  anulado      BOOLEAN NOT NULL DEFAULT false,
  usuario_id   UUID
);
CREATE INDEX idx_pagos_cliente ON pagos (cliente_id, fecha DESC);

-- ============================================================
-- CUENTA CORRIENTE (libro de debe / haber por cliente)
-- El saldo NO se guarda: se calcula sumando (ver vista v_saldos)
-- ============================================================
CREATE TABLE cta_cte_movimientos (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cliente_id    UUID NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  fecha         TIMESTAMPTZ NOT NULL DEFAULT now(),
  tipo          TEXT NOT NULL CHECK (tipo IN
                  ('venta','pago','devolucion','cancelacion','ajuste','saldo_inicial')),
  debe          NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (debe >= 0),   -- aumenta deuda
  haber         NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (haber >= 0),  -- disminuye deuda
  descripcion   TEXT,
  pedido_id     UUID REFERENCES pedidos(id),
  pago_id       UUID REFERENCES pagos(id),
  devolucion_id UUID REFERENCES devoluciones(id),
  usuario_id    UUID
);
CREATE INDEX idx_ctacte_cliente ON cta_cte_movimientos (cliente_id, fecha, id);
