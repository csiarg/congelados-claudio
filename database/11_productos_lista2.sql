-- ============================================================
-- CONGELADOS CLAUDIO · 11_productos_lista2.sql
-- Carga de 82 productos de "LISTA 2" (actualización 15/07/25).
-- Ejecutar en Supabase > SQL Editor. Se puede volver a correr: si el código
-- ya existe, actualiza descripción y precio (y el cambio queda en el historial).
--
-- · Cada producto se vende por BULTO (caja/bolsa); la presentación va en el nombre.
-- · El precio de la lista se carga como PRECIO DE VENTA BASE.
-- · Se crea un proveedor por marca (sirve para aumentos masivos por marca).
-- · 10 productos venían en $0: quedan cargados SIN PRECIO y no se pueden
--   vender hasta ponérselo (el sistema lo bloquea).
-- ============================================================
BEGIN;

INSERT INTO proveedores (nombre) VALUES
  ('3 Arroyos'), ('Aliward'), ('Bas'), ('Bast Frost'), ('Grangys'), ('Granjis'), ('McCain'), ('Saborigal'), ('Sadia')
ON CONFLICT (nombre) DO NOTHING;

SELECT set_config('app.motivo_precio', 'Lista 2 (15/07/25)', true);

WITH lista (codigo, descripcion, marca, rubro, precio) AS (VALUES
  ('GRA01', 'Patitas de pollo (5 kg)', 'Grangys', 'Rebozados congelados', 34000.00),
  ('GRA02', 'Patitas de pollo con J/Q (5 kg)', 'Grangys', 'Rebozados congelados', 36300.00),
  ('GRA03', 'Medallón de pollo (5 kg)', 'Grangys', 'Rebozados congelados', 34000.00),
  ('GRA04', 'Cañoncito de Muzzarella (6 kg)', 'Grangys', 'Rebozados congelados', 68900.00),
  ('GRA05', 'Medallón de pollo con J/Q (5 kg)', 'Grangys', 'Rebozados congelados', 36300.00),
  ('GRA06', 'Medallón de espinaca (5 kg)', 'Grangys', 'Rebozados congelados', 36300.00),
  ('GRA07', 'Nuggets de pollo gigante (6 kg)', 'Grangys', 'Rebozados congelados', 59200.00),
  ('GRA08', 'Nuggets de pollo Crocante (6 kg)', 'Grangys', 'Rebozados congelados', 53200.00),
  ('GRA09', 'Supremitas (5 kg)', 'Grangys', 'Rebozados congelados', 58000.00),
  ('GRA10', 'Bocaditos de Calabaza (5 kg)', 'Grangys', 'Rebozados congelados', 32200.00),
  ('GRA11', 'Bocaditos de Espinaca (5 kg)', 'Grangys', 'Rebozados congelados', 28800.00),
  ('GRA12', 'Bocaditos de Papa y Queso (5 kg)', 'Grangys', 'Rebozados congelados', 32800.00),
  ('GRA13', 'Bocaditos de Muzzarella (5 kg)', 'Grangys', 'Rebozados congelados', 52800.00),
  ('GRA14', 'Medallón de Merluza (5 kg)', 'Grangys', 'Rebozados congelados', 25100.00),
  ('GRA15', 'Bastón de Merluza (5 kg)', 'Grangys', 'Rebozados congelados', 25100.00),
  ('GRA16', 'Formita Marina de Merluza (5 kg)', 'Grangys', 'Rebozados congelados', 25100.00),
  ('GRA17', 'Dynos (5 kg)', 'Grangys', 'Rebozados congelados', 35460.00),
  ('MCC01', 'Tradicional (15 kg)', 'McCain', 'Papas y vegetales congelados', 81442.00),
  ('MCC02', 'Smile (9 kg)', 'McCain', 'Papas y vegetales congelados', 73830.00),
  ('MCC03', 'Noisette (10 kg)', 'McCain', 'Papas y vegetales congelados', 71520.00),
  ('MCC04', 'Crinkles (12,5 kg)', 'McCain', 'Papas y vegetales congelados', 0.00),
  ('MCC05', 'Rustica (15 kg)', 'McCain', 'Papas y vegetales congelados', 0.00),
  ('MCC06', 'Harvest con cascara (15 kg)', 'McCain', 'Papas y vegetales congelados', 0.00),
  ('MCC07', 'Farmpac (15 kg)', 'McCain', 'Papas y vegetales congelados', 0.00),
  ('MCC08', 'Fast Food corte fino (18 kg)', 'McCain', 'Papas y vegetales congelados', 0.00),
  ('MCC09', 'Americana tradicional recubierta (15 kg)', 'McCain', 'Papas y vegetales congelados', 0.00),
  ('MCC10', 'Americana corte fino recubierta (18 kg)', 'McCain', 'Papas y vegetales congelados', 0.00),
  ('MCC11', 'Aros de cebolla (10 kg)', 'McCain', 'Papas y vegetales congelados', 104500.00),
  ('MCC12', 'One fry (15 kg)', 'McCain', 'Papas y vegetales congelados', 53000.00),
  ('MCC13', 'Bite espinaca (10 kg)', 'McCain', 'Papas y vegetales congelados', 49955.00),
  ('MCC14', 'Acelga (10 kg)', 'McCain', 'Papas y vegetales congelados', 56590.00),
  ('MCC15', 'Arvejas (10 kg)', 'McCain', 'Papas y vegetales congelados', 67325.00),
  ('MCC16', 'Brócoli (10 kg)', 'McCain', 'Papas y vegetales congelados', 70931.00),
  ('MCC17', 'Chaucha (10 kg)', 'McCain', 'Papas y vegetales congelados', 60495.00),
  ('MCC18', 'Choclo (10 kg)', 'McCain', 'Papas y vegetales congelados', 65950.00),
  ('MCC19', 'Espinaca (10 kg)', 'McCain', 'Papas y vegetales congelados', 59835.00),
  ('MCC20', 'Jardinera (10 kg)', 'McCain', 'Papas y vegetales congelados', 63150.00),
  ('TAR01', 'Ricosaurios (8 kg)', '3 Arroyos', 'Rebozados congelados', 68740.00),
  ('TAR02', 'Medallón de Pollo (5 kg)', '3 Arroyos', 'Rebozados congelados', 0.00),
  ('TAR03', 'Nuggets a la tempura (10 kg)', '3 Arroyos', 'Rebozados congelados', 104600.00),
  ('BFR01', 'Tripa chinesca (2 u)', 'Bast Frost', 'Pescados y otros congelados', 62000.00),
  ('BFR02', 'Filet (5 kg)', 'Bast Frost', 'Pescados y otros congelados', 50820.00),
  ('BFR03', 'Filet a la romana (5 kg)', 'Bast Frost', 'Pescados y otros congelados', 33388.00),
  ('SAD01', 'Pechugas (6 kg)', 'Sadia', 'Pollo congelado', 45730.00),
  ('SAD02', 'Supremas (6 kg)', 'Sadia', 'Pollo congelado', 47586.00),
  ('SAD03', 'Nuggets (6 kg)', 'Sadia', 'Pollo congelado', 59920.00),
  ('BAS01', 'Rebozador (25 kg)', 'Bas', 'Secos: rebozadores y premezclas', 27030.00),
  ('BAS02', 'Pan Rayado (20 kg)', 'Bas', 'Secos: rebozadores y premezclas', 27030.00),
  ('BAS03', 'Batter Bas 30 (30 kg)', 'Bas', 'Secos: rebozadores y premezclas', 112000.00),
  ('BAS04', 'Batter Bas 5x25 (5 kg)', 'Bas', 'Secos: rebozadores y premezclas', 22500.00),
  ('BAS05', 'Integral chorizo colorado (1 kg)', 'Bas', 'Secos: rebozadores y premezclas', 6940.00),
  ('BAS06', 'Integral chorizo Fresco (1 kg)', 'Bas', 'Secos: rebozadores y premezclas', 5876.00),
  ('BAS07', 'Integral chorizo seco (1 kg)', 'Bas', 'Secos: rebozadores y premezclas', 6700.00),
  ('BAS08', 'Integral hamburguesa ahumada (1 kg)', 'Bas', 'Secos: rebozadores y premezclas', 5876.00),
  ('BAS09', 'Integral longaniza (1 kg)', 'Bas', 'Secos: rebozadores y premezclas', 6700.00),
  ('BAS10', 'Integral salame (1 kg)', 'Bas', 'Secos: rebozadores y premezclas', 6700.00),
  ('BAS11', 'Integral Salchicha Fresca (5 kg)', 'Bas', 'Secos: rebozadores y premezclas', 20928.00),
  ('BAS12', 'Integral Morcilla (5 kg)', 'Bas', 'Secos: rebozadores y premezclas', 25928.00),
  ('SAB01', 'Batter (Preparado para milanesa) (10 kg)', 'Saborigal', 'Secos: rebozadores y premezclas', 58000.00),
  ('SAB02', 'Batter (Preparado para milanesa) (1 kg)', 'Saborigal', 'Secos: rebozadores y premezclas', 5800.00),
  ('SAB03', 'Integral hamburguesa (1 kg)', 'Saborigal', 'Secos: rebozadores y premezclas', 6140.00),
  ('SAB04', 'Sabor humo en polvo (1 kg)', 'Saborigal', 'Secos: rebozadores y premezclas', 7260.00),
  ('SAB05', 'Integral salchicha fresca (1 kg)', 'Saborigal', 'Secos: rebozadores y premezclas', 6140.00),
  ('ALI01', 'Pan Rayado (25 kg)', 'Aliward', 'Secos: rebozadores y premezclas', 24500.00),
  ('ALI02', 'Rebozador (25 kg)', 'Aliward', 'Secos: rebozadores y premezclas', 24500.00),
  ('ALI03', 'Batter "Sol de campo" (25 kg)', 'Aliward', 'Secos: rebozadores y premezclas', 116000.00),
  ('ALI04', 'Batter "Sol de Campo" (5 kg)', 'Aliward', 'Secos: rebozadores y premezclas', 24200.00),
  ('ALI05', 'Pan Rayado "Sol de Campo" (20 kg)', 'Aliward', 'Secos: rebozadores y premezclas', 16140.00),
  ('ALI06', 'Pan Rayado "Sol de Campo" (5 kg)', 'Aliward', 'Secos: rebozadores y premezclas', 4535.00),
  ('ALI07', 'Pan Rayado "Sol de Campo" (12 x 400 g)', 'Aliward', 'Secos: rebozadores y premezclas', 7170.00),
  ('ALI08', 'Rebozador color (25 kg)', 'Aliward', 'Secos: rebozadores y premezclas', 16400.00),
  ('ALI09', 'Rebozador color (20 kg)', 'Aliward', 'Secos: rebozadores y premezclas', 13800.00),
  ('MCR01', 'Papas smiles (caritas) 12 x 600 g (7,2 kg)', 'McCain', 'Papas retail (minorista)', 46650.00),
  ('MCR02', 'Papas Noisette 16 x 600 g (9,6 kg)', 'McCain', 'Papas retail (minorista)', 54960.00),
  ('MCR03', 'Papas tradicional 16 x 700 g (11,2 kg)', 'McCain', 'Papas retail (minorista)', 46653.00),
  ('GRJ01', 'Arvejas (10 x1 kg)', 'Granjis', 'Vegetales congelados', 49740.00),
  ('GRJ02', 'Brócoli (10 x 750 g)', 'Granjis', 'Vegetales congelados', 50447.00),
  ('GRJ03', 'Cebolla (10 x 1 kg)', 'Granjis', 'Vegetales congelados', 0.00),
  ('GRJ04', 'Pimiento Rojo en cubos (10 x 1 kg)', 'Granjis', 'Vegetales congelados', 0.00),
  ('GRJ05', 'Choclo (10 x 1 kg)', 'Granjis', 'Vegetales congelados', 58154.00),
  ('GRJ06', 'Chaucha (10 x 1 kg)', 'Granjis', 'Vegetales congelados', 46328.00),
  ('GRJ07', 'Primavera (10 x 1 kg)', 'Granjis', 'Vegetales congelados', 44538.00)
)
INSERT INTO productos (codigo, descripcion, marca, rubro, unidad, proveedor_id, precio_venta)
SELECT l.codigo, l.descripcion, l.marca, l.rubro, 'bulto',
       (SELECT id FROM proveedores WHERE nombre = l.marca), l.precio
  FROM lista l
ON CONFLICT (codigo) DO UPDATE
   SET descripcion  = EXCLUDED.descripcion,
       marca        = EXCLUDED.marca,
       rubro        = EXCLUDED.rubro,
       proveedor_id = EXCLUDED.proveedor_id,
       precio_venta = EXCLUDED.precio_venta;

COMMIT;

-- Resumen
SELECT marca, count(*) AS productos, count(*) FILTER (WHERE precio_venta = 0) AS sin_precio
  FROM productos WHERE codigo ~ '^(GRA|MCC|MCR|TAR|BFR|SAD|BAS|SAB|ALI|GRJ)[0-9]'
 GROUP BY marca ORDER BY marca;
