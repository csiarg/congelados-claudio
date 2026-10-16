-- ============================================================
-- CONGELADOS CLAUDIO · Base de datos v2
-- 04_seguridad.sql  →  Quién puede ver y hacer qué (RLS + permisos)
-- Se puede volver a ejecutar.
--
--   admin    : todo
--   operario : ve todo; vende, cobra, devuelve, carga/descarga camiones; puede dar de alta clientes
--   consulta : solo lectura
--   sin perfil / inactivo / no logueado : nada
--
-- Stock, pedidos, cuenta corriente, compras y pagos NO se escriben directo
-- (ni siquiera el admin): solo a través de las funciones, para que todo cuadre.
-- ============================================================

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'configuracion','camiones','perfiles','proveedores','productos','precios_historico',
    'listas_precios','listas_precios_items','clientes','recorridos','stock','movimientos_stock',
    'compras','compras_items','pedidos','pedidos_items','devoluciones','devoluciones_items',
    'pagos','cta_cte_movimientos']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);

    -- Lectura: cualquier usuario activo (perfiles tiene su propia regla)
    IF t <> 'perfiles' THEN
      EXECUTE format('DROP POLICY IF EXISTS leer ON %I', t);
      EXECUTE format('CREATE POLICY leer ON %I FOR SELECT TO authenticated USING (tiene_acceso())', t);
    END IF;
  END LOOP;

  -- Escritura directa: solo admin, solo tablas maestras
  FOREACH t IN ARRAY ARRAY[
    'configuracion','camiones','proveedores','productos','listas_precios',
    'listas_precios_items','clientes']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS admin_escribe ON %I', t);
    EXECUTE format('CREATE POLICY admin_escribe ON %I FOR ALL TO authenticated USING (es_admin()) WITH CHECK (es_admin())', t);
  END LOOP;
END $$;

-- Operarios pueden dar de alta clientes nuevos en la calle
DROP POLICY IF EXISTS operario_alta_cliente ON clientes;
CREATE POLICY operario_alta_cliente ON clientes FOR INSERT TO authenticated
  WITH CHECK (puede_operar());

-- Perfiles: cada uno ve el suyo; admin ve y edita todos
DROP POLICY IF EXISTS ver_perfil ON perfiles;
CREATE POLICY ver_perfil ON perfiles FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR es_admin() OR tiene_acceso());
DROP POLICY IF EXISTS admin_perfiles ON perfiles;
CREATE POLICY admin_perfiles ON perfiles FOR UPDATE TO authenticated
  USING (es_admin()) WITH CHECK (es_admin());
DROP POLICY IF EXISTS admin_borra_perfiles ON perfiles;
CREATE POLICY admin_borra_perfiles ON perfiles FOR DELETE TO authenticated
  USING (es_admin());

-- ------------------------------------------------------------
-- Permisos de tablas: el público anónimo no ve nada
-- ------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- ------------------------------------------------------------
-- Permisos de funciones: por defecto nadie; luego se habilitan las públicas
-- ------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  mi_rol(), es_admin(), puede_operar(), tiene_acceso(), hoy(), normalizar_whatsapp(TEXT),
  precio_para(UUID, UUID), saldo_cliente(UUID),
  ajustar_stock(UUID, NUMERIC, UUID, TEXT, BOOLEAN),
  actualizar_precio(UUID, NUMERIC, TEXT),
  aumentar_precios(NUMERIC, UUID, TEXT, TEXT),
  registrar_compra(JSONB, UUID, TEXT, DATE, TEXT),
  abrir_recorrido(UUID, TEXT),
  cargar_camion(UUID, JSONB, TEXT),
  descargar_camion(UUID, JSONB, TEXT),
  cerrar_recorrido(UUID, BOOLEAN, TEXT),
  registrar_pago(UUID, NUMERIC, TEXT, TEXT, UUID),
  anular_pago(UUID, TEXT),
  ajustar_cta_cte(UUID, NUMERIC, TEXT, BOOLEAN),
  crear_pedido(UUID, JSONB, UUID, TEXT, TEXT, NUMERIC, TEXT),
  marcar_entregado(UUID),
  cancelar_pedido(UUID, TEXT),
  registrar_devolucion(UUID, JSONB, TEXT, UUID, BOOLEAN),
  buscar_productos(TEXT, UUID, UUID, INT),
  top_productos(DATE, DATE, UUID, UUID, INT, TEXT),
  resumen_dashboard(DATE, DATE)
TO authenticated;

-- Solo el servidor (Netlify Function con la service key) atiende WhatsApp
GRANT EXECUTE ON FUNCTION
  catalogo_whatsapp(TEXT, TEXT),
  crear_pedido_whatsapp(TEXT, JSONB, TEXT)
TO service_role;
