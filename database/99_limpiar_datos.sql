-- ============================================================
-- CONGELADOS CLAUDIO · 99_limpiar_datos.sql
-- ⚠️  BORRA TODOS LOS DATOS (productos, clientes, ventas, stock, etc.)
-- Conserva: usuarios/perfiles y configuración.
-- Usar UNA vez, después de probar con los datos demo y antes de cargar los reales.
-- ============================================================
BEGIN;

UPDATE perfiles SET camion_id = NULL;

-- Sin CASCADE a propósito: si alguna tabla nueva quedara afuera, falla en vez de borrar de más.
TRUNCATE
  cta_cte_movimientos, pagos, devoluciones_items, devoluciones,
  pedidos_items, pedidos, compras_items, compras,
  movimientos_stock, stock, recorridos,
  listas_precios_items, precios_historico,
  clientes, listas_precios, productos, proveedores
RESTART IDENTITY;

-- camiones lo referencia "perfiles" (que se conserva): se borra con DELETE
DELETE FROM camiones;

-- Numeración desde 1 (si existe la tabla de contadores)
DO $$ BEGIN
  IF to_regclass('public.contadores') IS NOT NULL THEN
    UPDATE contadores SET valor = 0;
  END IF;
END $$;

COMMIT;

SELECT 'Datos borrados. Usuarios conservados: ' || count(*) AS resultado FROM perfiles;
