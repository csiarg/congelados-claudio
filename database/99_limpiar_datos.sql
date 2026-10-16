-- ============================================================
-- CONGELADOS CLAUDIO · 99_limpiar_datos.sql
-- ⚠️  BORRA TODOS LOS DATOS (productos, clientes, ventas, stock, etc.)
-- Conserva: usuarios/perfiles y configuración.
-- Usar UNA vez, después de probar con los datos demo y antes de cargar los reales.
-- ============================================================
UPDATE perfiles SET camion_id = NULL;

TRUNCATE
  cta_cte_movimientos, pagos, devoluciones_items, devoluciones,
  pedidos_items, pedidos, compras_items, compras,
  movimientos_stock, stock, recorridos,
  listas_precios_items, precios_historico,
  clientes, listas_precios, productos, proveedores, camiones
RESTART IDENTITY CASCADE;
