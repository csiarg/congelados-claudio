-- ============================================================
-- CONGELADOS CLAUDIO · Base de datos v2
-- 02_funciones.sql  →  Lógica de negocio
-- Se puede volver a ejecutar para actualizar funciones.
--
-- Convención: las funciones que empiezan con "_" son internas
-- (no se pueden llamar desde la web). El resto se llaman con
-- supabase.rpc('nombre', {...}).
-- ============================================================

-- ============================================================
-- PERMISOS / UTILIDADES
-- ============================================================
CREATE OR REPLACE FUNCTION public.mi_rol()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT rol FROM perfiles WHERE user_id = auth.uid() AND activo;
$$;

CREATE OR REPLACE FUNCTION public.es_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(mi_rol() = 'admin', false);
$$;

CREATE OR REPLACE FUNCTION public.puede_operar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(mi_rol() IN ('admin','operario'), false);
$$;

CREATE OR REPLACE FUNCTION public.tiene_acceso()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT mi_rol() IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION public._exigir(p_ok BOOLEAN, p_msg TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(p_ok, false) THEN RAISE EXCEPTION '%', p_msg USING ERRCODE = 'P0001'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.hoy()
RETURNS DATE LANGUAGE sql STABLE AS $$
  SELECT (now() AT TIME ZONE 'America/Argentina/Buenos_Aires')::date;
$$;

-- Busca un producto a partir de {"producto_id": ...} o {"codigo": ...}
CREATE OR REPLACE FUNCTION public._producto_de(p_item JSONB)
RETURNS productos LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE v productos;
BEGIN
  IF p_item ? 'producto_id' AND NULLIF(p_item->>'producto_id','') IS NOT NULL THEN
    SELECT * INTO v FROM productos WHERE id = (p_item->>'producto_id')::uuid;
  ELSE
    SELECT * INTO v FROM productos WHERE upper(codigo) = upper(trim(p_item->>'codigo'));
  END IF;
  IF v.id IS NULL THEN
    RAISE EXCEPTION 'Producto no encontrado: %', COALESCE(p_item->>'producto_id', p_item->>'codigo', '?');
  END IF;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public._cantidad_de(p_item JSONB)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE c NUMERIC;
BEGIN
  c := NULLIF(p_item->>'cantidad','')::numeric;
  IF c IS NULL OR c <= 0 THEN RAISE EXCEPTION 'Cantidad inválida: %', p_item->>'cantidad'; END IF;
  RETURN c;
END $$;

-- ============================================================
-- STOCK: único punto donde se modifica el stock
-- p_camion NULL = depósito. p_delta positivo entra, negativo sale.
-- ============================================================
CREATE OR REPLACE FUNCTION public._mover_stock(
  p_producto    UUID,
  p_camion      UUID,
  p_delta       NUMERIC,
  p_tipo        TEXT,
  p_costo       NUMERIC DEFAULT NULL,
  p_recorrido   UUID DEFAULT NULL,
  p_pedido      UUID DEFAULT NULL,
  p_compra      UUID DEFAULT NULL,
  p_devolucion  UUID DEFAULT NULL,
  p_obs         TEXT DEFAULT NULL
) RETURNS NUMERIC LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_actual NUMERIC;
  v_nuevo  NUMERIC;
  v_desc   TEXT;
  v_lugar  TEXT;
BEGIN
  IF p_delta = 0 THEN RETURN NULL; END IF;

  INSERT INTO stock (producto_id, camion_id, cantidad)
  VALUES (p_producto, p_camion, 0)
  ON CONFLICT ON CONSTRAINT uq_stock DO NOTHING;

  SELECT cantidad INTO v_actual FROM stock
   WHERE producto_id = p_producto AND camion_id IS NOT DISTINCT FROM p_camion
   FOR UPDATE;

  v_nuevo := v_actual + p_delta;

  IF v_nuevo < 0 AND NOT (SELECT permitir_stock_negativo FROM configuracion WHERE id = 1) THEN
    SELECT descripcion INTO v_desc FROM productos WHERE id = p_producto;
    SELECT COALESCE('camión ' || numero, 'depósito') INTO v_lugar FROM (SELECT 1) x
      LEFT JOIN camiones c ON c.id = p_camion;
    RAISE EXCEPTION 'Stock insuficiente de "%" en %: hay %, se necesitan %',
      v_desc, v_lugar, trim_scale(v_actual), trim_scale(-p_delta);
  END IF;

  UPDATE stock SET cantidad = v_nuevo, updated_at = now()
   WHERE producto_id = p_producto AND camion_id IS NOT DISTINCT FROM p_camion;

  INSERT INTO movimientos_stock (producto_id, camion_id, tipo, cantidad, saldo, costo_unitario,
                                 recorrido_id, pedido_id, compra_id, devolucion_id, observacion, usuario_id)
  VALUES (p_producto, p_camion, p_tipo, p_delta, v_nuevo, p_costo,
          p_recorrido, p_pedido, p_compra, p_devolucion, p_obs, auth.uid());

  RETURN v_nuevo;
END $$;

-- Ajuste por conteo físico o merma (solo admin)
CREATE OR REPLACE FUNCTION public.ajustar_stock(
  p_producto_id    UUID,
  p_cantidad_real  NUMERIC,
  p_camion_id      UUID DEFAULT NULL,
  p_motivo         TEXT DEFAULT 'Conteo físico',
  p_es_merma       BOOLEAN DEFAULT false
) RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_actual NUMERIC;
BEGIN
  PERFORM _exigir(es_admin(), 'Solo un administrador puede ajustar stock');
  PERFORM _exigir(p_cantidad_real >= 0, 'La cantidad real no puede ser negativa');
  SELECT COALESCE(sum(cantidad), 0) INTO v_actual FROM stock
   WHERE producto_id = p_producto_id AND camion_id IS NOT DISTINCT FROM p_camion_id;
  RETURN _mover_stock(p_producto_id, p_camion_id, p_cantidad_real - v_actual,
                      CASE WHEN p_es_merma THEN 'merma' ELSE 'ajuste' END,
                      p_obs => p_motivo);
END $$;

-- ============================================================
-- PRECIOS
-- ============================================================
-- Precio de un producto para una lista (precio especial > % de la lista > precio base)
CREATE OR REPLACE FUNCTION public.precio_para(p_producto_id UUID, p_lista_id UUID DEFAULT NULL)
RETURNS NUMERIC LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(
           lpi.precio,
           round(p.precio_venta * (1 + COALESCE(l.ajuste_porcentaje, 0) / 100), 2))
    FROM productos p
    LEFT JOIN listas_precios l        ON l.id = p_lista_id AND l.activo
    LEFT JOIN listas_precios_items lpi ON lpi.lista_id = l.id AND lpi.producto_id = p.id
   WHERE p.id = p_producto_id;
$$;

CREATE OR REPLACE FUNCTION public.actualizar_precio(
  p_producto_id UUID, p_precio_nuevo NUMERIC, p_motivo TEXT DEFAULT 'Ajuste manual'
) RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM _exigir(es_admin(), 'Solo un administrador puede cambiar precios');
  PERFORM _exigir(p_precio_nuevo >= 0, 'Precio inválido');
  PERFORM set_config('app.motivo_precio', p_motivo, true);
  UPDATE productos SET precio_venta = round(p_precio_nuevo, 2) WHERE id = p_producto_id;
  PERFORM _exigir(FOUND, 'Producto no encontrado');
  RETURN round(p_precio_nuevo, 2);
END $$;

-- Aumento/rebaja masiva por % (filtrable por proveedor y/o rubro). Devuelve cuántos cambió.
CREATE OR REPLACE FUNCTION public.aumentar_precios(
  p_porcentaje   NUMERIC,
  p_proveedor_id UUID DEFAULT NULL,
  p_rubro        TEXT DEFAULT NULL,
  p_motivo       TEXT DEFAULT NULL
) RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE n INT;
BEGIN
  PERFORM _exigir(es_admin(), 'Solo un administrador puede cambiar precios');
  PERFORM _exigir(p_porcentaje > -100, 'Porcentaje inválido');
  PERFORM set_config('app.motivo_precio',
          COALESCE(p_motivo, 'Aumento masivo ' || trim_scale(p_porcentaje) || '%'), true);
  UPDATE productos
     SET precio_venta = round(precio_venta * (1 + p_porcentaje / 100), 2)
   WHERE activo
     AND (p_proveedor_id IS NULL OR proveedor_id = p_proveedor_id)
     AND (p_rubro IS NULL OR rubro ILIKE p_rubro);
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

-- ============================================================
-- COMPRAS → entran al depósito y recalculan COSTO PROMEDIO PONDERADO
--   costo nuevo = (stock_actual × costo_actual + cant_comprada × costo_compra)
--                 / (stock_actual + cant_comprada)
--   Ej.: 100 u a $1 + compro 100 u a $1,20  →  costo promedio $1,10
-- Si el producto tiene margen_porcentaje, el precio de venta se recalcula.
-- p_items: [{"producto_id"|"codigo": ..., "cantidad": 10, "costo_unitario": 1500}]
-- ============================================================
CREATE OR REPLACE FUNCTION public.registrar_compra(
  p_items         JSONB,
  p_proveedor_id  UUID DEFAULT NULL,
  p_comprobante   TEXT DEFAULT NULL,
  p_fecha         DATE DEFAULT NULL,
  p_observaciones TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_compra  UUID;
  v_numero  INT;
  v_item    JSONB;
  v_prod    productos;
  v_cant    NUMERIC;
  v_costo   NUMERIC;
  v_stock   NUMERIC;
  v_prom    NUMERIC;
  v_total   NUMERIC := 0;
BEGIN
  PERFORM _exigir(es_admin(), 'Solo un administrador puede registrar compras');
  PERFORM _exigir(jsonb_typeof(p_items) = 'array' AND jsonb_array_length(p_items) > 0, 'La compra no tiene productos');

  INSERT INTO compras (proveedor_id, fecha, comprobante, observaciones, usuario_id)
  VALUES (p_proveedor_id, COALESCE(p_fecha, hoy()), p_comprobante, p_observaciones, auth.uid())
  RETURNING id, numero INTO v_compra, v_numero;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_prod  := _producto_de(v_item);
    v_cant  := _cantidad_de(v_item);
    v_costo := NULLIF(v_item->>'costo_unitario','')::numeric;
    PERFORM _exigir(v_costo IS NOT NULL AND v_costo >= 0, 'Falta el costo de ' || v_prod.descripcion);

    -- releer con bloqueo (por si el mismo producto viene dos veces)
    SELECT * INTO v_prod FROM productos WHERE id = v_prod.id FOR UPDATE;
    SELECT GREATEST(COALESCE(sum(cantidad), 0), 0) INTO v_stock FROM stock WHERE producto_id = v_prod.id;

    IF v_stock = 0 OR v_prod.costo_promedio = 0 THEN
      v_prom := v_costo;
    ELSE
      v_prom := round((v_stock * v_prod.costo_promedio + v_cant * v_costo) / (v_stock + v_cant), 2);
    END IF;

    UPDATE productos SET costo_promedio = v_prom, costo_ultimo = v_costo WHERE id = v_prod.id;

    IF v_prod.margen_porcentaje IS NOT NULL THEN
      PERFORM set_config('app.motivo_precio', 'Compra #' || v_numero || ' (costo promedio + margen)', true);
      UPDATE productos SET precio_venta = round(v_prom * (1 + v_prod.margen_porcentaje / 100), 2)
       WHERE id = v_prod.id;
    END IF;

    INSERT INTO compras_items (compra_id, producto_id, cantidad, costo_unitario, costo_promedio_resultante, importe)
    VALUES (v_compra, v_prod.id, v_cant, v_costo, v_prom, round(v_cant * v_costo, 2));

    PERFORM _mover_stock(v_prod.id, NULL, v_cant, 'compra', v_costo, p_compra => v_compra,
                         p_obs => 'Compra #' || v_numero);
    v_total := v_total + round(v_cant * v_costo, 2);
  END LOOP;

  UPDATE compras SET total = v_total WHERE id = v_compra;
  RETURN jsonb_build_object('id', v_compra, 'numero', v_numero, 'total', v_total);
END $$;

-- ============================================================
-- RECORRIDOS Y CAMIONES (carga / descarga)
-- ============================================================
CREATE OR REPLACE FUNCTION public._recorrido_abierto(p_camion UUID)
RETURNS UUID LANGUAGE sql STABLE SET search_path = public, pg_temp AS $$
  SELECT id FROM recorridos WHERE camion_id = p_camion AND estado = 'en_curso';
$$;

CREATE OR REPLACE FUNCTION public._abrir_recorrido(p_camion UUID, p_chofer TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v UUID;
BEGIN
  v := _recorrido_abierto(p_camion);
  IF v IS NOT NULL THEN RETURN v; END IF;
  PERFORM _exigir(EXISTS (SELECT 1 FROM camiones WHERE id = p_camion AND activo), 'Camión inexistente o inactivo');
  INSERT INTO recorridos (camion_id, chofer_nombre, abierto_por)
  SELECT p_camion, COALESCE(p_chofer, chofer_nombre), auth.uid() FROM camiones WHERE id = p_camion
  RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.abrir_recorrido(p_camion_id UUID, p_chofer TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso');
  RETURN _abrir_recorrido(p_camion_id, p_chofer);
END $$;

-- Depósito → camión.  p_items: [{"producto_id"|"codigo": ..., "cantidad": 20}]
CREATE OR REPLACE FUNCTION public.cargar_camion(
  p_camion_id UUID, p_items JSONB, p_observacion TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_rec UUID; v_item JSONB; v_prod productos; v_cant NUMERIC;
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso para cargar camiones');
  PERFORM _exigir(jsonb_typeof(p_items) = 'array' AND jsonb_array_length(p_items) > 0, 'No hay productos para cargar');
  v_rec := _abrir_recorrido(p_camion_id);
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_prod := _producto_de(v_item);
    v_cant := _cantidad_de(v_item);
    PERFORM _mover_stock(v_prod.id, NULL,        -v_cant, 'carga_camion', v_prod.costo_promedio, v_rec, p_obs => p_observacion);
    PERFORM _mover_stock(v_prod.id, p_camion_id,  v_cant, 'carga_camion', v_prod.costo_promedio, v_rec, p_obs => p_observacion);
  END LOOP;
  RETURN v_rec;
END $$;

-- Camión → depósito.  p_items NULL = descarga TODO lo que queda arriba.
CREATE OR REPLACE FUNCTION public.descargar_camion(
  p_camion_id UUID, p_items JSONB DEFAULT NULL, p_observacion TEXT DEFAULT NULL
) RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_rec UUID; v_item JSONB; v_prod productos; v_cant NUMERIC; n INT := 0; r RECORD;
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso para descargar camiones');
  v_rec := _recorrido_abierto(p_camion_id);
  IF p_items IS NULL THEN
    FOR r IN SELECT producto_id, cantidad FROM stock WHERE camion_id = p_camion_id AND cantidad > 0 LOOP
      PERFORM _mover_stock(r.producto_id, p_camion_id, -r.cantidad, 'descarga_camion', NULL, v_rec, p_obs => p_observacion);
      PERFORM _mover_stock(r.producto_id, NULL,          r.cantidad, 'descarga_camion', NULL, v_rec, p_obs => p_observacion);
      n := n + 1;
    END LOOP;
  ELSE
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
      v_prod := _producto_de(v_item);
      v_cant := _cantidad_de(v_item);
      PERFORM _mover_stock(v_prod.id, p_camion_id, -v_cant, 'descarga_camion', NULL, v_rec, p_obs => p_observacion);
      PERFORM _mover_stock(v_prod.id, NULL,          v_cant, 'descarga_camion', NULL, v_rec, p_obs => p_observacion);
      n := n + 1;
    END LOOP;
  END IF;
  RETURN n;
END $$;

-- Cierra la jornada: descarga lo que sobró (opcional) y guarda el resumen
CREATE OR REPLACE FUNCTION public.cerrar_recorrido(
  p_camion_id UUID, p_descargar BOOLEAN DEFAULT true, p_observaciones TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_rec UUID; v_resumen JSONB;
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso');
  v_rec := _recorrido_abierto(p_camion_id);
  PERFORM _exigir(v_rec IS NOT NULL, 'El camión no tiene un recorrido abierto');

  IF p_descargar THEN
    PERFORM descargar_camion(p_camion_id, NULL, 'Cierre de recorrido');
  END IF;

  SELECT jsonb_build_object(
    'productos', COALESCE((
      SELECT jsonb_agg(x ORDER BY x->>'descripcion') FROM (
        SELECT jsonb_build_object(
          'codigo', p.codigo, 'descripcion', p.descripcion, 'unidad', p.unidad,
          'cargado',    COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo = 'carga_camion'), 0),
          'vendido',    COALESCE(-sum(m.cantidad) FILTER (WHERE m.tipo IN ('venta','cancelacion')), 0),
          'devuelto',   COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo = 'devolucion'), 0),
          'descargado', COALESCE(-sum(m.cantidad) FILTER (WHERE m.tipo = 'descarga_camion'), 0),
          'ajustes',    COALESCE(sum(m.cantidad) FILTER (WHERE m.tipo IN ('ajuste','merma')), 0)
        ) AS x
        FROM movimientos_stock m JOIN productos p ON p.id = m.producto_id
        WHERE m.recorrido_id = v_rec AND m.camion_id = p_camion_id
        GROUP BY p.codigo, p.descripcion, p.unidad) t), '[]'::jsonb),
    'pedidos',      (SELECT count(*) FROM pedidos WHERE recorrido_id = v_rec AND estado <> 'cancelado'),
    'total_ventas', (SELECT COALESCE(sum(total), 0) FROM pedidos WHERE recorrido_id = v_rec AND estado <> 'cancelado'),
    'total_devoluciones', (SELECT COALESCE(sum(d.total), 0) FROM devoluciones d
                            JOIN pedidos pe ON pe.id = d.pedido_id WHERE pe.recorrido_id = v_rec),
    'cobranzas', COALESCE((SELECT jsonb_object_agg(medio, total) FROM (
                    SELECT medio, sum(monto) total FROM pagos
                     WHERE recorrido_id = v_rec AND NOT anulado GROUP BY medio) c), '{}'::jsonb),
    'quedo_en_camion', COALESCE((SELECT sum(cantidad) FROM stock WHERE camion_id = p_camion_id), 0)
  ) INTO v_resumen;

  UPDATE recorridos
     SET estado = 'cerrado', cerrado_por = auth.uid(), cerrado_at = now(),
         resumen = v_resumen, observaciones = COALESCE(p_observaciones, observaciones)
   WHERE id = v_rec;

  RETURN v_resumen;
END $$;

-- ============================================================
-- CUENTA CORRIENTE Y COBRANZAS
-- ============================================================
CREATE OR REPLACE FUNCTION public.saldo_cliente(p_cliente_id UUID)
RETURNS NUMERIC LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE(sum(debe - haber), 0) FROM cta_cte_movimientos WHERE cliente_id = p_cliente_id;
$$;

CREATE OR REPLACE FUNCTION public._registrar_pago(
  p_cliente_id UUID, p_monto NUMERIC, p_medio TEXT, p_referencia TEXT,
  p_camion_id UUID, p_pedido_id UUID
) RETURNS UUID LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE v_pago UUID; v_num INT; v_rec UUID;
BEGIN
  PERFORM _exigir(p_monto > 0, 'El monto del pago debe ser mayor a cero');
  IF p_camion_id IS NOT NULL THEN v_rec := _recorrido_abierto(p_camion_id); END IF;
  INSERT INTO pagos (cliente_id, monto, medio, referencia, camion_id, recorrido_id, pedido_id, usuario_id)
  VALUES (p_cliente_id, round(p_monto, 2), COALESCE(p_medio, 'efectivo'), p_referencia,
          p_camion_id, v_rec, p_pedido_id, auth.uid())
  RETURNING id, numero INTO v_pago, v_num;
  INSERT INTO cta_cte_movimientos (cliente_id, tipo, haber, descripcion, pago_id, pedido_id, usuario_id)
  VALUES (p_cliente_id, 'pago', round(p_monto, 2),
          'Pago #' || v_num || ' (' || COALESCE(p_medio, 'efectivo') || ')', v_pago, p_pedido_id, auth.uid());
  RETURN v_pago;
END $$;

CREATE OR REPLACE FUNCTION public.registrar_pago(
  p_cliente_id UUID, p_monto NUMERIC, p_medio TEXT DEFAULT 'efectivo',
  p_referencia TEXT DEFAULT NULL, p_camion_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v UUID;
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso para registrar cobranzas');
  v := _registrar_pago(p_cliente_id, p_monto, p_medio, p_referencia, p_camion_id, NULL);
  RETURN jsonb_build_object('pago_id', v, 'saldo', saldo_cliente(p_cliente_id));
END $$;

CREATE OR REPLACE FUNCTION public.anular_pago(p_pago_id UUID, p_motivo TEXT DEFAULT NULL)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v pagos;
BEGIN
  PERFORM _exigir(es_admin(), 'Solo un administrador puede anular pagos');
  SELECT * INTO v FROM pagos WHERE id = p_pago_id FOR UPDATE;
  PERFORM _exigir(v.id IS NOT NULL, 'Pago no encontrado');
  PERFORM _exigir(NOT v.anulado, 'El pago ya estaba anulado');
  UPDATE pagos SET anulado = true WHERE id = p_pago_id;
  INSERT INTO cta_cte_movimientos (cliente_id, tipo, debe, descripcion, pago_id, usuario_id)
  VALUES (v.cliente_id, 'ajuste', v.monto,
          'Anulación pago #' || v.numero || COALESCE(' – ' || p_motivo, ''), v.id, auth.uid());
  RETURN saldo_cliente(v.cliente_id);
END $$;

-- Ajuste manual o saldo inicial (monto + = más deuda, - = menos deuda)
CREATE OR REPLACE FUNCTION public.ajustar_cta_cte(
  p_cliente_id UUID, p_monto NUMERIC, p_motivo TEXT, p_es_saldo_inicial BOOLEAN DEFAULT false
) RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM _exigir(es_admin(), 'Solo un administrador puede ajustar cuentas corrientes');
  PERFORM _exigir(p_monto <> 0, 'El monto no puede ser cero');
  PERFORM _exigir(NULLIF(trim(p_motivo), '') IS NOT NULL, 'Indicá el motivo del ajuste');
  INSERT INTO cta_cte_movimientos (cliente_id, tipo, debe, haber, descripcion, usuario_id)
  VALUES (p_cliente_id, CASE WHEN p_es_saldo_inicial THEN 'saldo_inicial' ELSE 'ajuste' END,
          GREATEST(p_monto, 0), GREATEST(-p_monto, 0), p_motivo, auth.uid());
  RETURN saldo_cliente(p_cliente_id);
END $$;

-- ============================================================
-- PEDIDOS
-- Venta desde camión (p_camion_id): descuenta stock del camión, queda ENTREGADO.
-- Pedido al depósito (sin camión, ej. WhatsApp): descuenta stock del depósito,
--   queda PENDIENTE hasta que se marca entregado.
-- Siempre: genera DEBE en la cuenta corriente; si se cobra en el acto, el HABER.
-- p_items: [{"producto_id"|"codigo": ..., "cantidad": 2, "precio_unitario": (solo admin)}]
-- ============================================================
CREATE OR REPLACE FUNCTION public._crear_pedido(
  p_cliente_id  UUID,
  p_items       JSONB,
  p_camion_id   UUID,
  p_origen      TEXT,
  p_notas       TEXT,
  p_precio_libre BOOLEAN,
  p_whatsapp    TEXT DEFAULT NULL
) RETURNS pedidos LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
DECLARE
  v_cli   clientes;
  v_ped   pedidos;
  v_rec   UUID;
  v_item  JSONB;
  v_prod  productos;
  v_cant  NUMERIC;
  v_precio NUMERIC;
  v_total NUMERIC := 0;
  v_costo NUMERIC := 0;
  v_saldo NUMERIC;
BEGIN
  SELECT * INTO v_cli FROM clientes WHERE id = p_cliente_id;
  PERFORM _exigir(v_cli.id IS NOT NULL, 'Cliente no encontrado');
  PERFORM _exigir(v_cli.activo, 'El cliente "' || v_cli.nombre || '" está inactivo');
  PERFORM _exigir(jsonb_typeof(p_items) = 'array' AND jsonb_array_length(p_items) > 0, 'El pedido no tiene productos');

  IF p_camion_id IS NOT NULL THEN
    v_rec := _abrir_recorrido(p_camion_id);
  END IF;

  INSERT INTO pedidos (cliente_id, estado, origen, camion_id, recorrido_id, reparto_camion_id,
                       lista_precio_id, notas, whatsapp_origen, usuario_id, entregado_at)
  VALUES (v_cli.id,
          CASE WHEN p_camion_id IS NOT NULL THEN 'entregado' ELSE 'pendiente' END,
          COALESCE(p_origen, 'app'), p_camion_id, v_rec,
          COALESCE(p_camion_id, v_cli.camion_id),
          v_cli.lista_precio_id, p_notas, p_whatsapp, auth.uid(),
          CASE WHEN p_camion_id IS NOT NULL THEN now() END)
  RETURNING * INTO v_ped;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_prod := _producto_de(v_item);
    v_cant := _cantidad_de(v_item);
    PERFORM _exigir(v_prod.activo, 'El producto "' || v_prod.descripcion || '" está dado de baja');

    IF p_precio_libre AND NULLIF(v_item->>'precio_unitario','') IS NOT NULL THEN
      v_precio := round((v_item->>'precio_unitario')::numeric, 2);
    ELSE
      v_precio := precio_para(v_prod.id, v_cli.lista_precio_id);
    END IF;
    PERFORM _exigir(v_precio > 0, 'El producto "' || v_prod.descripcion || '" no tiene precio cargado');

    INSERT INTO pedidos_items (pedido_id, producto_id, cantidad, precio_unitario, costo_unitario, importe)
    VALUES (v_ped.id, v_prod.id, v_cant, v_precio, v_prod.costo_promedio, round(v_cant * v_precio, 2));

    PERFORM _mover_stock(v_prod.id, p_camion_id, -v_cant, 'venta', v_prod.costo_promedio,
                         v_rec, v_ped.id, p_obs => 'Pedido #' || v_ped.numero);

    v_total := v_total + round(v_cant * v_precio, 2);
    v_costo := v_costo + round(v_cant * v_prod.costo_promedio, 2);
  END LOOP;

  UPDATE pedidos SET total = v_total, costo_total = v_costo WHERE id = v_ped.id
  RETURNING * INTO v_ped;

  -- Límite de crédito (0 = sin límite)
  IF v_cli.limite_credito > 0 AND NOT p_precio_libre THEN
    v_saldo := saldo_cliente(v_cli.id);
    PERFORM _exigir(v_saldo + v_total <= v_cli.limite_credito,
      format('El cliente supera su límite de crédito ($%s). Saldo actual $%s + pedido $%s',
             v_cli.limite_credito, v_saldo, v_total));
  END IF;

  INSERT INTO cta_cte_movimientos (cliente_id, tipo, debe, descripcion, pedido_id, usuario_id)
  VALUES (v_cli.id, 'venta', v_total, 'Pedido #' || v_ped.numero, v_ped.id, auth.uid());

  RETURN v_ped;
END $$;

CREATE OR REPLACE FUNCTION public.crear_pedido(
  p_cliente_id  UUID,
  p_items       JSONB,
  p_camion_id   UUID DEFAULT NULL,
  p_origen      TEXT DEFAULT 'app',
  p_notas       TEXT DEFAULT NULL,
  p_pago_monto  NUMERIC DEFAULT 0,
  p_pago_medio  TEXT DEFAULT 'efectivo'
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v pedidos;
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso para cargar pedidos');
  v := _crear_pedido(p_cliente_id, p_items, p_camion_id, p_origen, p_notas, es_admin());
  IF COALESCE(p_pago_monto, 0) > 0 THEN
    PERFORM _registrar_pago(p_cliente_id, p_pago_monto, p_pago_medio, 'Pedido #' || v.numero, p_camion_id, v.id);
  END IF;
  RETURN jsonb_build_object('id', v.id, 'numero', v.numero, 'total', v.total,
                            'estado', v.estado, 'saldo_cliente', saldo_cliente(p_cliente_id));
END $$;

CREATE OR REPLACE FUNCTION public.marcar_entregado(p_pedido_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso');
  UPDATE pedidos SET estado = 'entregado', entregado_at = now()
   WHERE id = p_pedido_id AND estado = 'pendiente';
  PERFORM _exigir(FOUND, 'El pedido no existe o no está pendiente');
END $$;

-- Cancela: devuelve la mercadería a donde salió y revierte la cuenta corriente.
-- Operario: solo pedidos pendientes. Admin: cualquiera.
CREATE OR REPLACE FUNCTION public.cancelar_pedido(p_pedido_id UUID, p_motivo TEXT DEFAULT NULL)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v pedidos; v_destino UUID; v_rec UUID; r RECORD; v_monto NUMERIC;
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso');
  SELECT * INTO v FROM pedidos WHERE id = p_pedido_id FOR UPDATE;
  PERFORM _exigir(v.id IS NOT NULL, 'Pedido no encontrado');
  PERFORM _exigir(v.estado <> 'cancelado', 'El pedido ya está cancelado');
  PERFORM _exigir(v.estado = 'pendiente' OR es_admin(), 'Solo un administrador puede cancelar un pedido entregado');

  -- vuelve al camión si su recorrido sigue abierto; si no, al depósito
  IF v.camion_id IS NOT NULL AND _recorrido_abierto(v.camion_id) = v.recorrido_id THEN
    v_destino := v.camion_id; v_rec := v.recorrido_id;
  END IF;

  FOR r IN SELECT producto_id, cantidad - cantidad_devuelta AS cant, costo_unitario
             FROM pedidos_items WHERE pedido_id = v.id AND cantidad - cantidad_devuelta > 0 LOOP
    PERFORM _mover_stock(r.producto_id, v_destino, r.cant, 'cancelacion', r.costo_unitario,
                         v_rec, v.id, p_obs => 'Cancelación pedido #' || v.numero);
  END LOOP;

  v_monto := v.total - COALESCE((SELECT sum(total) FROM devoluciones WHERE pedido_id = v.id), 0);
  IF v_monto > 0 THEN
    INSERT INTO cta_cte_movimientos (cliente_id, tipo, haber, descripcion, pedido_id, usuario_id)
    VALUES (v.cliente_id, 'cancelacion', v_monto,
            'Cancelación pedido #' || v.numero || COALESCE(' – ' || p_motivo, ''), v.id, auth.uid());
  END IF;

  UPDATE pedidos SET estado = 'cancelado', cancelado_at = now(), motivo_cancelacion = p_motivo
   WHERE id = v.id;
  RETURN saldo_cliente(v.cliente_id);
END $$;

-- Devolución parcial de un pedido.
-- p_items: [{"producto_id"|"codigo": ..., "cantidad": 1}]
-- p_camion_id: a qué camión vuelve la mercadería (NULL = depósito)
-- p_vuelve_a_stock = false si el producto se descarta (no reingresa)
CREATE OR REPLACE FUNCTION public.registrar_devolucion(
  p_pedido_id      UUID,
  p_items          JSONB,
  p_motivo         TEXT DEFAULT NULL,
  p_camion_id      UUID DEFAULT NULL,
  p_vuelve_a_stock BOOLEAN DEFAULT true
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_ped pedidos; v_dev UUID; v_num INT; v_item JSONB; v_prod productos; v_cant NUMERIC;
  v_pi pedidos_items; v_total NUMERIC := 0; v_rec UUID;
BEGIN
  PERFORM _exigir(puede_operar(), 'Sin permiso para registrar devoluciones');
  SELECT * INTO v_ped FROM pedidos WHERE id = p_pedido_id FOR UPDATE;
  PERFORM _exigir(v_ped.id IS NOT NULL, 'Pedido no encontrado');
  PERFORM _exigir(v_ped.estado <> 'cancelado', 'El pedido está cancelado');
  PERFORM _exigir(jsonb_typeof(p_items) = 'array' AND jsonb_array_length(p_items) > 0, 'No hay productos a devolver');

  IF p_camion_id IS NOT NULL THEN v_rec := _recorrido_abierto(p_camion_id); END IF;

  INSERT INTO devoluciones (pedido_id, cliente_id, camion_id, motivo, vuelve_a_stock, usuario_id)
  VALUES (v_ped.id, v_ped.cliente_id, p_camion_id, p_motivo, p_vuelve_a_stock, auth.uid())
  RETURNING id, numero INTO v_dev, v_num;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_prod := _producto_de(v_item);
    v_cant := _cantidad_de(v_item);
    SELECT * INTO v_pi FROM pedidos_items
     WHERE pedido_id = v_ped.id AND producto_id = v_prod.id
       AND cantidad - cantidad_devuelta >= v_cant
     ORDER BY id LIMIT 1 FOR UPDATE;
    PERFORM _exigir(v_pi.id IS NOT NULL,
      'No se puede devolver ' || trim_scale(v_cant) || ' de "' || v_prod.descripcion || '": supera lo vendido en el pedido');

    UPDATE pedidos_items SET cantidad_devuelta = cantidad_devuelta + v_cant WHERE id = v_pi.id;
    INSERT INTO devoluciones_items (devolucion_id, pedido_item_id, producto_id, cantidad, precio_unitario, importe)
    VALUES (v_dev, v_pi.id, v_prod.id, v_cant, v_pi.precio_unitario, round(v_cant * v_pi.precio_unitario, 2));

    IF p_vuelve_a_stock THEN
      PERFORM _mover_stock(v_prod.id, p_camion_id, v_cant, 'devolucion', v_pi.costo_unitario,
                           v_rec, v_ped.id, p_devolucion => v_dev, p_obs => 'Devolución #' || v_num);
    END IF;
    v_total := v_total + round(v_cant * v_pi.precio_unitario, 2);
  END LOOP;

  UPDATE devoluciones SET total = v_total WHERE id = v_dev;
  INSERT INTO cta_cte_movimientos (cliente_id, tipo, haber, descripcion, pedido_id, devolucion_id, usuario_id)
  VALUES (v_ped.cliente_id, 'devolucion', v_total,
          'Devolución #' || v_num || ' (pedido #' || v_ped.numero || ')', v_ped.id, v_dev, auth.uid());

  RETURN jsonb_build_object('id', v_dev, 'numero', v_num, 'total', v_total,
                            'saldo_cliente', saldo_cliente(v_ped.cliente_id));
END $$;

-- ============================================================
-- WHATSAPP (solo lo llama el servidor con la service key, nunca el navegador)
-- ============================================================
-- Catálogo con el precio de ESE cliente y si hay stock en depósito
CREATE OR REPLACE FUNCTION public.catalogo_whatsapp(p_whatsapp TEXT, p_busqueda TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE v_cli clientes;
BEGIN
  SELECT * INTO v_cli FROM clientes WHERE whatsapp = normalizar_whatsapp(p_whatsapp) AND activo;
  IF v_cli.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cliente_no_registrado');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'cliente', jsonb_build_object('id', v_cli.id, 'nombre', v_cli.nombre,
                                  'saldo', saldo_cliente(v_cli.id)),
    'productos', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'codigo', p.codigo, 'descripcion', p.descripcion, 'unidad', p.unidad,
               'precio', precio_para(p.id, v_cli.lista_precio_id),
               'disponible', COALESCE(s.cantidad, 0) > 0) ORDER BY p.rubro, p.descripcion)
        FROM productos p
        LEFT JOIN stock s ON s.producto_id = p.id AND s.camion_id IS NULL
       WHERE p.activo AND p.precio_venta > 0
         AND (p_busqueda IS NULL OR unaccent(lower(p.descripcion)) LIKE '%' || unaccent(lower(p_busqueda)) || '%')
    ), '[]'::jsonb));
END $$;

-- Crea el pedido. Nunca lanza error: devuelve {ok:false, error:"..."} para que el bot lo conteste.
-- p_items: [{"codigo": "POL01", "cantidad": 3}]
CREATE OR REPLACE FUNCTION public.crear_pedido_whatsapp(
  p_whatsapp TEXT, p_items JSONB, p_notas TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_cli clientes; v pedidos;
BEGIN
  SELECT * INTO v_cli FROM clientes WHERE whatsapp = normalizar_whatsapp(p_whatsapp);
  IF v_cli.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'cliente_no_registrado');
  END IF;

  BEGIN
    v := _crear_pedido(v_cli.id, p_items, NULL, 'whatsapp', p_notas, false, normalizar_whatsapp(p_whatsapp));
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
  END;

  RETURN jsonb_build_object(
    'ok', true, 'numero', v.numero, 'total', v.total, 'cliente', v_cli.nombre,
    'saldo', saldo_cliente(v_cli.id),
    'items', (SELECT jsonb_agg(jsonb_build_object(
                'descripcion', p.descripcion, 'cantidad', i.cantidad, 'unidad', p.unidad,
                'precio', i.precio_unitario, 'importe', i.importe) ORDER BY i.id)
                FROM pedidos_items i JOIN productos p ON p.id = i.producto_id
               WHERE i.pedido_id = v.id));
END $$;

-- ============================================================
-- BÚSQUEDA Y REPORTES
-- ============================================================
-- Buscador para pantalla de venta: precio según lista y stock en depósito / camión
CREATE OR REPLACE FUNCTION public.buscar_productos(
  p_termino TEXT, p_lista_id UUID DEFAULT NULL, p_camion_id UUID DEFAULT NULL, p_limite INT DEFAULT 30
) RETURNS TABLE (id UUID, codigo TEXT, descripcion TEXT, marca TEXT, rubro TEXT, unidad TEXT,
                 precio NUMERIC, stock_deposito NUMERIC, stock_camion NUMERIC, destacado BOOLEAN)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE palabras TEXT[];
BEGIN
  PERFORM _exigir(tiene_acceso(), 'Sin acceso');
  palabras := ARRAY(SELECT w FROM unnest(regexp_split_to_array(lower(unaccent(trim(COALESCE(p_termino,'')))), '\s+')) w WHERE w <> '');
  RETURN QUERY
  SELECT p.id, p.codigo, p.descripcion, p.marca, p.rubro, p.unidad,
         precio_para(p.id, p_lista_id),
         COALESCE(sd.cantidad, 0), COALESCE(sc.cantidad, 0), p.destacado
    FROM productos p
    LEFT JOIN stock sd ON sd.producto_id = p.id AND sd.camion_id IS NULL
    LEFT JOIN stock sc ON sc.producto_id = p.id AND sc.camion_id = p_camion_id
   WHERE p.activo
     AND (cardinality(palabras) = 0 OR NOT EXISTS (
            SELECT 1 FROM unnest(palabras) w
             WHERE lower(unaccent(p.descripcion || ' ' || p.codigo || ' ' || COALESCE(p.marca,''))) NOT LIKE '%' || w || '%'))
   ORDER BY p.destacado DESC,
            (lower(unaccent(p.descripcion)) LIKE lower(unaccent(trim(COALESCE(p_termino,'')))) || '%') DESC,
            p.descripcion
   LIMIT p_limite;
END $$;

-- TOP N productos más vendidos (neto de devoluciones). Fechas inclusive.
CREATE OR REPLACE FUNCTION public.top_productos(
  p_desde DATE DEFAULT NULL, p_hasta DATE DEFAULT NULL,
  p_camion_id UUID DEFAULT NULL, p_proveedor_id UUID DEFAULT NULL,
  p_limite INT DEFAULT 10, p_ordenar_por TEXT DEFAULT 'importe'   -- 'importe' | 'cantidad'
) RETURNS TABLE (posicion INT, producto_id UUID, codigo TEXT, descripcion TEXT, unidad TEXT,
                 cantidad NUMERIC, importe NUMERIC, ganancia NUMERIC, pedidos BIGINT, participacion_pct NUMERIC)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  PERFORM _exigir(tiene_acceso(), 'Sin acceso');
  RETURN QUERY
  WITH v AS (
    SELECT i.producto_id,
           sum(i.cantidad - i.cantidad_devuelta) AS cant,
           sum((i.cantidad - i.cantidad_devuelta) * i.precio_unitario) AS imp,
           sum((i.cantidad - i.cantidad_devuelta) * (i.precio_unitario - i.costo_unitario)) AS gan,
           count(DISTINCT i.pedido_id) AS ped
      FROM pedidos_items i
      JOIN pedidos pe ON pe.id = i.pedido_id
      JOIN productos pr ON pr.id = i.producto_id
     WHERE pe.estado <> 'cancelado'
       AND (pe.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date
           BETWEEN COALESCE(p_desde, hoy() - 29) AND COALESCE(p_hasta, hoy())
       AND (p_camion_id IS NULL OR COALESCE(pe.camion_id, pe.reparto_camion_id) = p_camion_id)
       AND (p_proveedor_id IS NULL OR pr.proveedor_id = p_proveedor_id)
     GROUP BY i.producto_id
  ), tot AS (SELECT NULLIF(sum(imp), 0) AS t FROM v)
  SELECT (row_number() OVER (ORDER BY CASE WHEN p_ordenar_por = 'cantidad' THEN v.cant ELSE v.imp END DESC))::int,
         p.id, p.codigo, p.descripcion, p.unidad,
         trim_scale(v.cant), round(v.imp, 2), round(v.gan, 2), v.ped,
         round(v.imp / (SELECT t FROM tot) * 100, 1)
    FROM v JOIN productos p ON p.id = v.producto_id
   WHERE v.cant > 0
   ORDER BY 1
   LIMIT p_limite;
END $$;

-- Números generales para el dashboard
CREATE OR REPLACE FUNCTION public.resumen_dashboard(p_desde DATE DEFAULT NULL, p_hasta DATE DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE d DATE := COALESCE(p_desde, hoy() - 29); h DATE := COALESCE(p_hasta, hoy()); r JSONB;
BEGIN
  PERFORM _exigir(tiene_acceso(), 'Sin acceso');
  WITH pe AS (
    SELECT * FROM pedidos
     WHERE estado <> 'cancelado'
       AND (fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date BETWEEN d AND h)
  SELECT jsonb_build_object(
    'desde', d, 'hasta', h,
    'ventas',        (SELECT COALESCE(sum(total), 0) FROM pe),
    'devoluciones',  (SELECT COALESCE(sum(dv.total), 0) FROM devoluciones dv
                       WHERE (dv.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date BETWEEN d AND h),
    'ganancia_bruta',(SELECT COALESCE(sum(total - costo_total), 0) FROM pe),
    'pedidos',       (SELECT count(*) FROM pe),
    'ticket_promedio',(SELECT COALESCE(round(avg(total), 2), 0) FROM pe),
    'pedidos_whatsapp',(SELECT count(*) FROM pe WHERE origen = 'whatsapp'),
    'pendientes_entrega',(SELECT count(*) FROM pedidos WHERE estado = 'pendiente'),
    'cobranzas',     (SELECT COALESCE(sum(monto), 0) FROM pagos
                       WHERE NOT anulado AND (fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date BETWEEN d AND h),
    'deuda_clientes',(SELECT COALESCE(sum(s), 0) FROM (SELECT sum(debe - haber) s FROM cta_cte_movimientos
                       GROUP BY cliente_id HAVING sum(debe - haber) > 0) x),
    'stock_valorizado',(SELECT COALESCE(round(sum(s.cantidad * p.costo_promedio), 2), 0)
                         FROM stock s JOIN productos p ON p.id = s.producto_id WHERE s.cantidad > 0),
    'productos_bajo_minimo',(SELECT count(*) FROM (
                         SELECT p.id FROM productos p LEFT JOIN stock s ON s.producto_id = p.id
                          WHERE p.activo AND p.stock_minimo > 0
                          GROUP BY p.id, p.stock_minimo HAVING COALESCE(sum(s.cantidad), 0) < p.stock_minimo) x)
  ) INTO r;
  RETURN r;
END $$;
