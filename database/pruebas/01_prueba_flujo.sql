-- Prueba del circuito completo (Postgres local con 00_simular_supabase.sql). NO ejecutar en Supabase.
\set ON_ERROR_STOP 1
\pset footer off
CREATE SCHEMA IF NOT EXISTS pruebas;
GRANT USAGE ON SCHEMA pruebas TO authenticated, anon, service_role;
CREATE OR REPLACE FUNCTION pruebas.debe_fallar(p_sql TEXT, p_esperado TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RAISE EXCEPTION 'FALLO DE PRUEBA: debía dar error "%" y no lo dio: %', p_esperado, p_sql;
EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FALLO DE PRUEBA%' OR SQLERRM NOT ILIKE '%' || p_esperado || '%' THEN RAISE; END IF;
  RETURN 'OK (rechazado): ' || SQLERRM;
END $$;
CREATE OR REPLACE FUNCTION pruebas.verificar(p_ok BOOLEAN, p_desc TEXT) RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(p_ok,false) THEN RAISE EXCEPTION 'FALLO DE PRUEBA: %', p_desc; END IF;
  RETURN 'OK: ' || p_desc;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pruebas TO authenticated, anon, service_role;

-- ===== ADMIN: hace operario a Pepe y le asigna el C-01 =====
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
UPDATE perfiles SET rol = 'operario', camion_id = (SELECT id FROM camiones WHERE numero = 'C-01')
 WHERE email = 'pepe@test.com';
SELECT pruebas.verificar((SELECT rol FROM perfiles WHERE email='pepe@test.com') = 'operario', 'admin cambia rol');

-- ===== OPERARIO PEPE =====
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
SELECT pruebas.debe_fallar($$UPDATE perfiles SET rol='admin' WHERE email='pepe@test.com' RETURNING 1$$, '') AS "operario no puede hacerse admin"
 WHERE false; -- (UPDATE sin permiso devuelve 0 filas; lo verificamos abajo)
UPDATE perfiles SET rol = 'admin' WHERE email = 'pepe@test.com';
SELECT pruebas.verificar(mi_rol() = 'operario', 'operario NO puede auto-ascenderse');

\echo '--- Carga del camión C-01'
SELECT cargar_camion((SELECT id FROM camiones WHERE numero='C-01'),
  '[{"codigo":"POL01","cantidad":30},{"codigo":"REB01","cantidad":10},{"codigo":"CAR01","cantidad":20},{"codigo":"PAP01","cantidad":8}]') IS NOT NULL AS cargado;
SELECT pruebas.verificar((SELECT stock_deposito FROM v_stock WHERE codigo='POL01') = 170
                     AND (SELECT stock_camiones FROM v_stock WHERE codigo='POL01') = 30, 'depósito 200→170, camión 30');
SELECT pruebas.debe_fallar($$SELECT cargar_camion((SELECT id FROM camiones WHERE numero='C-01'), '[{"codigo":"PES01","cantidad":500}]')$$,
                           'Stock insuficiente');
SELECT pruebas.debe_fallar($$INSERT INTO stock (producto_id, cantidad) SELECT id, 9999 FROM productos LIMIT 1$$, 'row-level security');

\echo '--- Venta en la calle a Don Tito (lista Mayorista -10%), a cuenta corriente'
SELECT crear_pedido((SELECT id FROM clientes WHERE nombre='Almacén Don Tito'),
  '[{"codigo":"POL01","cantidad":5},{"codigo":"REB01","cantidad":2},{"codigo":"POL01","cantidad":1,"precio_unitario":1}]',
  (SELECT id FROM camiones WHERE numero='C-01')) AS pedido1 \gset
SELECT :'pedido1';
-- POL01 costo 3800 +35% = 5130, -10% = 4617 ; REB01 4100*1.35=5535 -10% = 4981.50 ; el precio_unitario del operario se ignora
SELECT pruebas.verificar((:'pedido1'::jsonb->>'total')::numeric = 6*4617 + 2*4981.50, 'precios por lista e ignora precio manual del operario');
SELECT pruebas.verificar((:'pedido1'::jsonb->>'saldo_cliente')::numeric = 45000 + 6*4617 + 2*4981.50, 'deuda = saldo anterior + venta');
SELECT pruebas.verificar((SELECT cantidad FROM v_stock_camiones WHERE camion='C-01' AND codigo='POL01') = 24, 'camión POL01 30→24');

\echo '--- Venta contado al Kiosco (cobra en el acto)'
SELECT crear_pedido((SELECT id FROM clientes WHERE nombre='Kiosco El Pibe'),
  '[{"codigo":"CAR01","cantidad":3}]', (SELECT id FROM camiones WHERE numero='C-01'),
  'app', NULL, 3*4185, 'efectivo') AS pedido2 \gset
SELECT pruebas.verificar((:'pedido2'::jsonb->>'saldo_cliente')::numeric = 0, 'contado: saldo queda en 0');

\echo '--- Devolución de 1 kg de pechuga de Don Tito, vuelve al camión'
SELECT registrar_devolucion((:'pedido1'::jsonb->>'id')::uuid, '[{"codigo":"POL01","cantidad":1}]',
  'Bolsa rota', (SELECT id FROM camiones WHERE numero='C-01')) AS dev \gset
SELECT pruebas.verificar((SELECT cantidad FROM v_stock_camiones WHERE camion='C-01' AND codigo='POL01') = 25, 'devolución vuelve al camión');
SELECT pruebas.debe_fallar(format($$SELECT registrar_devolucion(%L, '[{"codigo":"REB01","cantidad":5}]')$$, :'pedido1'::jsonb->>'id'), 'supera lo vendido');

\echo '--- Cobro parcial a Don Tito'
SELECT registrar_pago((SELECT id FROM clientes WHERE nombre='Almacén Don Tito'), 20000, 'transferencia', 'Comp. 123',
                      (SELECT id FROM camiones WHERE numero='C-01'));
SELECT fecha::date, tipo, descripcion, debe, haber, saldo FROM v_cta_cte WHERE cliente='Almacén Don Tito' ORDER BY id;

\echo '--- Límite de crédito (Despensa María, límite 150.000)'
SELECT pruebas.debe_fallar($$SELECT crear_pedido((SELECT id FROM clientes WHERE nombre='Despensa María'),
  '[{"codigo":"POL01","cantidad":24},{"codigo":"REB01","cantidad":8}]', (SELECT id FROM camiones WHERE numero='C-01'))$$, 'límite de crédito');
SELECT pruebas.verificar((SELECT cantidad FROM v_stock_camiones WHERE camion='C-01' AND codigo='POL01') = 25, 'pedido rechazado no toca stock');

-- ===== WHATSAPP (servidor con service key) =====
RESET ROLE;
SET ROLE service_role;
SELECT set_config('request.jwt.claim.sub', '', false);
\echo '--- Pedido por WhatsApp de Super Familia'
SELECT crear_pedido_whatsapp('+54 9 11 6000-0004', '[{"codigo":"car02","cantidad":3},{"codigo":"HEL01","cantidad":2}]', 'Entregar a la mañana') AS wa \gset
SELECT jsonb_pretty(:'wa'::jsonb);
SELECT pruebas.verificar((:'wa'::jsonb->>'ok')::boolean, 'pedido WA creado');
SELECT pruebas.verificar((SELECT stock_deposito FROM v_stock WHERE codigo='CAR02') = 37, 'WA descuenta del depósito');
SELECT pruebas.verificar((SELECT estado || '/' || camion_reparto FROM v_pedidos WHERE origen='whatsapp') = 'pendiente/C-02', 'WA queda pendiente para el camión del cliente');
SELECT crear_pedido_whatsapp('11 9999-9999', '[{"codigo":"CAR02","cantidad":1}]') AS "número desconocido";
SELECT crear_pedido_whatsapp('1160000004', '[{"codigo":"HEL02","cantidad":99}]') AS "sin stock";
SELECT crear_pedido_whatsapp('1160000004', '[{"codigo":"XXX","cantidad":1}]') AS "código inexistente";
SELECT jsonb_array_length(catalogo_whatsapp('1160000004')->'productos') AS productos_catalogo,
       catalogo_whatsapp('1160000004')->'productos'->0 AS ejemplo;
RESET ROLE;

-- Un usuario logueado NO puede usar las funciones de WhatsApp
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
SELECT pruebas.debe_fallar($$SELECT crear_pedido_whatsapp('1160000004','[]')$$, 'permission denied');

-- ===== ADMIN: compra con nuevo costo → costo promedio =====
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
\echo '--- Compra de 195 kg de pechuga a $4.560 (antes $3.800, hay 195 kg en stock total)'
SELECT stock_total FROM v_stock WHERE codigo='POL01';
SELECT registrar_compra('[{"codigo":"POL01","cantidad":195,"costo_unitario":4560}]',
                        (SELECT id FROM proveedores WHERE nombre='Granja del Sol'), 'FC A 0001-00012999');
SELECT pruebas.verificar(costo_promedio = 4180 AND precio_venta = 5643, 'misma cantidad: (3800+4560)/2 = 4180 ; precio = 4180*1.35')
  FROM productos WHERE codigo='POL01';
SELECT precio_anterior, precio_nuevo, costo_promedio, variacion_pct, motivo FROM precios_historico ORDER BY id DESC LIMIT 1;

\echo '--- Aumento masivo 8% a Helados'
SELECT aumentar_precios(8, NULL, 'helados', 'Lista nueva Polares');

\echo '--- Operario no puede cancelar un pedido entregado; admin cancela el de WhatsApp'
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
SELECT pruebas.debe_fallar(format('SELECT cancelar_pedido(%L)', :'pedido2'::jsonb->>'id'), 'administrador');
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
SELECT cancelar_pedido((SELECT id FROM pedidos WHERE origen='whatsapp'), 'Cliente se arrepintió');
SELECT pruebas.verificar((SELECT stock_deposito FROM v_stock WHERE codigo='CAR02') = 40, 'cancelación devuelve al depósito');
SELECT pruebas.verificar(saldo = 0, 'cancelación revierte cta cte') FROM v_saldos WHERE nombre='Super Familia';

\echo '--- Cierre del recorrido C-01 (descarga lo que sobró)'
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
SELECT jsonb_pretty(cerrar_recorrido((SELECT id FROM camiones WHERE numero='C-01')));
SELECT pruebas.verificar(NOT EXISTS (SELECT 1 FROM v_stock_camiones WHERE camion='C-01'), 'camión vacío tras cierre');
SELECT pruebas.verificar((SELECT stock_deposito FROM v_stock WHERE codigo='POL01') = 170 + 25 + 195, 'sobrante vuelve al depósito');

\echo '--- TOP 10 y resumen'
SELECT posicion, codigo, descripcion, cantidad, importe, ganancia, pedidos, participacion_pct FROM top_productos();
SELECT jsonb_pretty(resumen_dashboard());

-- ===== CONSULTA (gerente) =====
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
SELECT pruebas.verificar((SELECT count(*) FROM v_stock) = 15, 'consulta ve el stock');
SELECT pruebas.debe_fallar($$SELECT crear_pedido((SELECT id FROM clientes LIMIT 1), '[{"codigo":"POL01","cantidad":1}]')$$, 'Sin permiso');
UPDATE productos SET precio_venta = 1;
SELECT pruebas.verificar(NOT EXISTS (SELECT 1 FROM productos WHERE precio_venta = 1), 'consulta no puede modificar precios');

-- ===== Usuario desactivado =====
RESET ROLE;
UPDATE perfiles SET activo = false WHERE email = 'gerente@test.com';
SET ROLE authenticated;
SELECT pruebas.verificar((SELECT count(*) FROM productos) = 0, 'usuario inactivo no ve nada');
RESET ROLE;
UPDATE perfiles SET activo = true WHERE email = 'gerente@test.com';

-- ===== Anónimo =====
SET ROLE anon;
SELECT pruebas.debe_fallar('SELECT * FROM productos', 'permission denied');
SELECT pruebas.debe_fallar($$SELECT crear_pedido(gen_random_uuid(), '[]')$$, 'permission denied');
RESET ROLE;

\echo '--- Kardex de la pechuga'
SELECT fecha::time(0), ubicacion, tipo, cantidad, saldo, observacion FROM v_movimientos_stock WHERE codigo='POL01' ORDER BY id;
\echo '=========== TODAS LAS PRUEBAS PASARON ==========='
