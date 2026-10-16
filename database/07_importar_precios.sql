-- ============================================================
-- CONGELADOS CLAUDIO · 07_importar_precios.sql
-- Importación masiva de precios desde una planilla (pantalla Administración).
--   p_lista_id NULL  → actualiza el PRECIO BASE de cada producto (queda en el historial)
--   p_lista_id = una lista → carga/actualiza el PRECIO ESPECIAL de cada producto en esa lista
-- p_items: [{"codigo":"GRA01","precio":35000}, ...]
-- Ejecutar una vez en Supabase > SQL Editor. Se puede volver a ejecutar.
-- ============================================================
CREATE OR REPLACE FUNCTION public.importar_precios(
  p_items    JSONB,
  p_lista_id UUID DEFAULT NULL,
  p_motivo   TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_item JSONB; v_prod UUID; v_precio NUMERIC; v_cod TEXT;
  n_ok INT := 0; n_igual INT := 0; v_no TEXT[] := '{}'; v_mal TEXT[] := '{}';
BEGIN
  PERFORM _exigir(es_admin(), 'Solo un administrador puede importar precios');
  PERFORM _exigir(jsonb_typeof(p_items) = 'array' AND jsonb_array_length(p_items) > 0, 'La planilla no tiene filas');
  IF p_lista_id IS NOT NULL THEN
    PERFORM _exigir(EXISTS (SELECT 1 FROM listas_precios WHERE id = p_lista_id), 'Lista de precios inexistente');
  END IF;
  PERFORM set_config('app.motivo_precio', COALESCE(NULLIF(trim(p_motivo), ''), 'Importación de planilla'), true);

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_cod := upper(trim(v_item->>'codigo'));
    CONTINUE WHEN v_cod IS NULL OR v_cod = '';
    v_precio := NULLIF(v_item->>'precio', '')::numeric;
    IF v_precio IS NULL OR v_precio < 0 THEN v_mal := v_mal || v_cod; CONTINUE; END IF;
    SELECT id INTO v_prod FROM productos WHERE upper(codigo) = v_cod;
    IF v_prod IS NULL THEN v_no := v_no || v_cod; CONTINUE; END IF;

    IF p_lista_id IS NULL THEN
      UPDATE productos SET precio_venta = round(v_precio, 2)
       WHERE id = v_prod AND precio_venta IS DISTINCT FROM round(v_precio, 2);
    ELSE
      INSERT INTO listas_precios_items (lista_id, producto_id, precio, updated_at)
      VALUES (p_lista_id, v_prod, round(v_precio, 2), now())
      ON CONFLICT (lista_id, producto_id) DO UPDATE
        SET precio = EXCLUDED.precio, updated_at = now()
        WHERE listas_precios_items.precio IS DISTINCT FROM EXCLUDED.precio;
    END IF;
    IF FOUND THEN n_ok := n_ok + 1; ELSE n_igual := n_igual + 1; END IF;
  END LOOP;

  RETURN jsonb_build_object('actualizados', n_ok, 'sin_cambios', n_igual,
                            'no_encontrados', to_jsonb(v_no), 'precio_invalido', to_jsonb(v_mal));
END $$;

REVOKE EXECUTE ON FUNCTION public.importar_precios(JSONB, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.importar_precios(JSONB, UUID, TEXT) TO authenticated;

-- Precios de todos los productos para una lista (para ver y descargar la lista)
CREATE OR REPLACE FUNCTION public.precios_de_lista(p_lista_id UUID DEFAULT NULL)
RETURNS TABLE (codigo TEXT, descripcion TEXT, marca TEXT, rubro TEXT, precio_base NUMERIC,
               precio_lista NUMERIC, especial BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM _exigir(tiene_acceso(), 'Sin acceso');
  RETURN QUERY
  SELECT p.codigo, p.descripcion, p.marca, p.rubro, p.precio_venta,
         precio_para(p.id, p_lista_id),
         (lpi.producto_id IS NOT NULL)
    FROM productos p
    LEFT JOIN listas_precios_items lpi ON lpi.lista_id = p_lista_id AND lpi.producto_id = p.id
   WHERE p.activo
   ORDER BY p.marca NULLS LAST, p.codigo;
END $$;
REVOKE EXECUTE ON FUNCTION public.precios_de_lista(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.precios_de_lista(UUID) TO authenticated;
