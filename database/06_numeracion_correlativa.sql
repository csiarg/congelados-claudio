-- ============================================================
-- CONGELADOS CLAUDIO · 06_numeracion_correlativa.sql
-- Numeración SIN HUECOS para pedidos, pagos y devoluciones.
-- Antes, si una venta se rechazaba (ej. falta de stock) igual "gastaba"
-- un número y quedaban saltos (#1, #3, #4…). Con un contador que se
-- deshace junto con la operación fallida, los números quedan correlativos.
--
-- Si ya instalaste la base: ejecutá ESTE archivo una vez en el SQL Editor.
-- (Ya viene incluido en 00_INSTALAR_TODO.sql para instalaciones nuevas.)
-- ============================================================

CREATE TABLE IF NOT EXISTS contadores (
  nombre TEXT PRIMARY KEY,
  valor  INT NOT NULL DEFAULT 0
);
ALTER TABLE contadores ENABLE ROW LEVEL SECURITY;   -- nadie lo lee directo
REVOKE ALL ON contadores FROM anon, authenticated;

INSERT INTO contadores (nombre, valor)
SELECT 'pedidos',      COALESCE(max(numero), 0) FROM pedidos      ON CONFLICT (nombre) DO NOTHING;
INSERT INTO contadores (nombre, valor)
SELECT 'pagos',        COALESCE(max(numero), 0) FROM pagos        ON CONFLICT (nombre) DO NOTHING;
INSERT INTO contadores (nombre, valor)
SELECT 'devoluciones', COALESCE(max(numero), 0) FROM devoluciones ON CONFLICT (nombre) DO NOTHING;

CREATE OR REPLACE FUNCTION public._proximo_numero(p_nombre TEXT)
RETURNS INT LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp AS $$
  UPDATE contadores SET valor = valor + 1 WHERE nombre = p_nombre RETURNING valor;
$$;
REVOKE EXECUTE ON FUNCTION public._proximo_numero(TEXT) FROM PUBLIC, anon, authenticated;

ALTER TABLE pedidos      ALTER COLUMN numero DROP IDENTITY IF EXISTS;
ALTER TABLE pedidos      ALTER COLUMN numero SET DEFAULT _proximo_numero('pedidos');
ALTER TABLE pagos        ALTER COLUMN numero DROP IDENTITY IF EXISTS;
ALTER TABLE pagos        ALTER COLUMN numero SET DEFAULT _proximo_numero('pagos');
ALTER TABLE devoluciones ALTER COLUMN numero DROP IDENTITY IF EXISTS;
ALTER TABLE devoluciones ALTER COLUMN numero SET DEFAULT _proximo_numero('devoluciones');
