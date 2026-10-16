-- ============================================================
-- CONGELADOS CLAUDIO · Base de datos v2
-- 05_datos_demo.sql  →  Datos de PRUEBA (opcional)
--
-- REQUISITO: haber creado tu usuario en Authentication (queda admin).
-- Para borrar todo esto antes de arrancar en serio: 99_limpiar_datos.sql
-- ============================================================

BEGIN;

-- Actuar como el primer admin (las funciones exigen un usuario con permiso)
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM perfiles WHERE rol = 'admin' AND activo ORDER BY created_at LIMIT 1), true);

DO $$ BEGIN
  IF NOT es_admin() THEN
    RAISE EXCEPTION 'Primero creá tu usuario en Supabase > Authentication > Users (queda como admin)';
  END IF;
END $$;

-- ---------- Proveedores ----------
INSERT INTO proveedores (nombre, telefono) VALUES
  ('Granja del Sol',   '11 4000-1000'),
  ('Frigorífico Sur',  '11 4000-2000'),
  ('Helados Polares',  '11 4000-3000');

-- ---------- Listas de precios ----------
INSERT INTO listas_precios (nombre, descripcion, ajuste_porcentaje) VALUES
  ('Minorista',  'Precio de lista',              0),
  ('Mayorista',  'Comercios con compra semanal', -10),
  ('Revendedor', 'Revendedores por volumen',     -15);

-- ---------- Camiones ----------
INSERT INTO camiones (numero, patente, descripcion, chofer_nombre, chofer_telefono) VALUES
  ('C-01', 'AB123CD', 'Kangoo térmica',  'Pepe',  '11 5000-0001'),
  ('C-02', 'AC456EF', 'Iveco con equipo', 'Rubén', '11 5000-0002');

-- ---------- Productos (margen 35% → el precio se calcula solo al comprar) ----------
INSERT INTO productos (codigo, descripcion, marca, rubro, unidad, proveedor_id, margen_porcentaje, stock_minimo, destacado)
SELECT x.codigo, x.descripcion, x.marca, x.rubro, x.unidad,
       (SELECT id FROM proveedores WHERE nombre = x.prov), 35, x.minimo, x.dest
FROM (VALUES
  ('POL01', 'Pechuga de pollo congelada',      'Granja del Sol', 'Pollo',      'kg',     'Granja del Sol',  20, true),
  ('POL02', 'Patamuslo de pollo',              'Granja del Sol', 'Pollo',      'kg',     'Granja del Sol',  20, false),
  ('POL03', 'Suprema rebozada x 1 kg',         'Granja del Sol', 'Rebozados',  'unidad', 'Granja del Sol',  15, false),
  ('REB01', 'Medallón de pollo x 12',          'Granja del Sol', 'Rebozados',  'caja',   'Granja del Sol',  10, true),
  ('REB02', 'Nuggets de pollo x 1 kg',         'Granja del Sol', 'Rebozados',  'unidad', 'Granja del Sol',  10, false),
  ('REB03', 'Milanesa de soja x 6',            'Granja del Sol', 'Rebozados',  'unidad', 'Granja del Sol',  10, false),
  ('CAR01', 'Hamburguesa de carne x 4',        'Frigorífico Sur','Carnes',     'caja',   'Frigorífico Sur', 20, true),
  ('CAR02', 'Hamburguesa de carne x 20',       'Frigorífico Sur','Carnes',     'caja',   'Frigorífico Sur', 10, false),
  ('CAR03', 'Milanesa de carne rebozada',      'Frigorífico Sur','Carnes',     'kg',     'Frigorífico Sur', 15, false),
  ('PAP01', 'Papas bastón prefritas x 2,5 kg', 'Frigorífico Sur','Vegetales',  'unidad', 'Frigorífico Sur', 20, true),
  ('VEG01', 'Espinaca congelada x 500 g',      'Frigorífico Sur','Vegetales',  'unidad', 'Frigorífico Sur', 10, false),
  ('PES01', 'Filet de merluza',                'Frigorífico Sur','Pescados',   'kg',     'Frigorífico Sur', 10, false),
  ('HEL01', 'Helado 1 kg surtido',             'Polares',        'Helados',    'unidad', 'Helados Polares', 10, false),
  ('HEL02', 'Palito helado x 20',              'Polares',        'Helados',    'caja',   'Helados Polares',  5, false),
  ('EMP01', 'Empanadas de carne x 12',         'Frigorífico Sur','Elaborados', 'caja',   'Frigorífico Sur', 10, false)
) AS x(codigo, descripcion, marca, rubro, unidad, prov, minimo, dest);

-- ---------- Compras iniciales (cargan stock en depósito y fijan costo + precio) ----------
SELECT registrar_compra(
  '[{"codigo":"POL01","cantidad":200,"costo_unitario":3800},
    {"codigo":"POL02","cantidad":150,"costo_unitario":2600},
    {"codigo":"POL03","cantidad":80, "costo_unitario":5200},
    {"codigo":"REB01","cantidad":60, "costo_unitario":4100},
    {"codigo":"REB02","cantidad":60, "costo_unitario":4800},
    {"codigo":"REB03","cantidad":40, "costo_unitario":2300}]',
  (SELECT id FROM proveedores WHERE nombre = 'Granja del Sol'), 'FC A 0001-00012345');

SELECT registrar_compra(
  '[{"codigo":"CAR01","cantidad":100,"costo_unitario":3100},
    {"codigo":"CAR02","cantidad":40, "costo_unitario":13500},
    {"codigo":"CAR03","cantidad":70, "costo_unitario":6900},
    {"codigo":"PAP01","cantidad":90, "costo_unitario":5600},
    {"codigo":"VEG01","cantidad":50, "costo_unitario":1450},
    {"codigo":"PES01","cantidad":40, "costo_unitario":8200},
    {"codigo":"EMP01","cantidad":50, "costo_unitario":5900}]',
  (SELECT id FROM proveedores WHERE nombre = 'Frigorífico Sur'), 'FC A 0003-00098765');

SELECT registrar_compra(
  '[{"codigo":"HEL01","cantidad":40,"costo_unitario":4300},
    {"codigo":"HEL02","cantidad":15,"costo_unitario":9800}]',
  (SELECT id FROM proveedores WHERE nombre = 'Helados Polares'), 'FC A 0002-00004567');

-- ---------- Clientes ----------
INSERT INTO clientes (nombre, razon_social, direccion, localidad, telefono, whatsapp,
                      lista_precio_id, camion_id, condicion_pago, limite_credito)
SELECT x.nombre, x.rs, x.dir, x.loc, x.tel, x.tel,
       (SELECT id FROM listas_precios WHERE nombre = x.lista),
       (SELECT id FROM camiones WHERE numero = x.cam), x.cond, x.lim
FROM (VALUES
  ('Almacén Don Tito',   'Tito SRL',          'Av. San Martín 1200', 'Morón',     '11 15 6000-0001', 'Mayorista',  'C-01', 'cta_cte', 300000),
  ('Rotisería La Esquina',NULL,               'Belgrano 455',        'Morón',     '11 6000-0002',    'Mayorista',  'C-01', 'cta_cte', 0),
  ('Kiosco El Pibe',     NULL,                'Rivadavia 18000',     'Haedo',     '011 6000-0003',   'Minorista',  'C-01', 'contado', 0),
  ('Super Familia',      'Familia Hnos SA',   'Mitre 900',           'Castelar',  '+54 9 11 6000-0004','Revendedor','C-02', 'cta_cte', 800000),
  ('Bar El Tano',        NULL,                'Sarmiento 321',       'Ituzaingó', '11-6000-0005',    'Minorista',  'C-02', 'contado', 0),
  ('Despensa María',     NULL,                'Alem 77',             'Ituzaingó', '1160000006',      'Mayorista',  'C-02', 'cta_cte', 150000)
) AS x(nombre, rs, dir, loc, tel, lista, cam, cond, lim);

-- Saldo que ya traía un cliente
SELECT ajustar_cta_cte((SELECT id FROM clientes WHERE nombre = 'Almacén Don Tito'),
                       45000, 'Saldo anterior al sistema', true);

COMMIT;
