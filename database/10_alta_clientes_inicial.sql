-- ============================================================
-- CONGELADOS CLAUDIO · 10_alta_clientes_inicial.sql
-- Alta de 86 clientes (75 de la planilla 1 + 11 de la planilla 2).
-- Ejecutar en Supabase > SQL Editor. Se puede correr más de una vez:
-- si un cliente con el mismo nombre ya existe, no lo duplica.
-- Quedan como CONTADO, lista base y sin camión. En "observaciones" dice
-- de qué planilla vino, para después asignarles camión o lista en grupo.
-- ============================================================
WITH nuevos (nombre, planilla) AS (VALUES
  ('Adrian Fenix Pollo', 'Planilla 1'),
  ('Alejandro chancheria', 'Planilla 1'),
  ('Andres chino colectora', 'Planilla 1'),
  ('Ariel Agüero', 'Planilla 1'),
  ('Ariel Agüero (cuñado)', 'Planilla 1'),
  ('Atessa Carniceria Malvinas', 'Planilla 1'),
  ('Atessa Granja', 'Planilla 1'),
  ('Bettiana Soule', 'Planilla 1'),
  ('Carlos Raffo', 'Planilla 1'),
  ('Carlos Raffo 2', 'Planilla 1'),
  ('Cesar Granja', 'Planilla 1'),
  ('Chino Juan', 'Planilla 1'),
  ('Chiqui Leo', 'Planilla 1'),
  ('Chiqui Leo Batter', 'Planilla 1'),
  ('Claudio Achuras', 'Planilla 1'),
  ('Clinica Alcorta', 'Planilla 1'),
  ('Cordobes', 'Planilla 1'),
  ('Corte Argento Juan', 'Planilla 1'),
  ('Cristian Delgado', 'Planilla 1'),
  ('Cristian Manteiga', 'Planilla 1'),
  ('Cristian Villalba', 'Planilla 1'),
  ('Davincho Porreca', 'Planilla 1'),
  ('Diego Jhonn Patiño', 'Planilla 1'),
  ('Dora vecina', 'Planilla 1'),
  ('Dos Belen', 'Planilla 1'),
  ('El Capricho (carniceria)', 'Planilla 1'),
  ('El Capricho 2 (Carniceria)', 'Planilla 1'),
  ('Erramuspe', 'Planilla 1'),
  ('Florencia Cartosciello 2', 'Planilla 1'),
  ('Florencia Cartosciello pollo', 'Planilla 1'),
  ('Florencia Latas', 'Planilla 1'),
  ('Franco Alasio 1', 'Planilla 1'),
  ('Granja Mar (Leonardo)', 'Planilla 1'),
  ('Gusty Cholito', 'Planilla 1'),
  ('Horacio Villaba', 'Planilla 1'),
  ('Jose Santinelli', 'Planilla 1'),
  ('Juan Fraternidad', 'Planilla 1'),
  ('Juan Maio', 'Planilla 1'),
  ('Juan Triangulo', 'Planilla 1'),
  ('Karina Ex Pipi Cucu', 'Planilla 1'),
  ('Karina Pipi Cucu Cuenta', 'Planilla 1'),
  ('La Estaca Parrilla pollo', 'Planilla 1'),
  ('Liliana', 'Planilla 1'),
  ('Lorena', 'Planilla 1'),
  ('Lucho Las Artes', 'Planilla 1'),
  ('Luis Fortuna', 'Planilla 1'),
  ('Luis Soria', 'Planilla 1'),
  ('Maria Rotonda', 'Planilla 1'),
  ('Mariano Acuña', 'Planilla 1'),
  ('Mariano Acuña FB Carnes', 'Planilla 1'),
  ('Mariano Kursewics', 'Planilla 1'),
  ('Martin Caseros', 'Planilla 1'),
  ('Mauricio El 57', 'Planilla 1'),
  ('Mechi congelados', 'Planilla 1'),
  ('Monica', 'Planilla 1'),
  ('Morales', 'Planilla 1'),
  ('Noelia Saenz Peña', 'Planilla 1'),
  ('Norma (Cocina de la abuela)', 'Planilla 1'),
  ('Parrilla Pola', 'Planilla 1'),
  ('Picolli (un supermercado)', 'Planilla 1'),
  ('Pizza y Faina', 'Planilla 1'),
  ('Pollolandia', 'Planilla 1'),
  ('Prado Guillermo', 'Planilla 1'),
  ('Ricardo Bicentenario', 'Planilla 1'),
  ('Ricardo Fraternidad', 'Planilla 1'),
  ('Rodrigo granja Yrigoyen', 'Planilla 1'),
  ('Roxana', 'Planilla 1'),
  ('Sebastian Gonzales Vaccaro', 'Planilla 1'),
  ('Sebita vaccaro', 'Planilla 1'),
  ('Sergio Barcia', 'Planilla 1'),
  ('Sergio Guemes', 'Planilla 1'),
  ('Simon', 'Planilla 1'),
  ('Tres Mor', 'Planilla 1'),
  ('Vanessa', 'Planilla 1'),
  ('Willy Almacen', 'Planilla 1'),
  ('Adrian Soles', 'Planilla 2'),
  ('Alberto cañon', 'Planilla 2'),
  ('Chiche Cañon', 'Planilla 2'),
  ('Chino Izar Pablo', 'Planilla 2'),
  ('Emanuel Azcuenaga', 'Planilla 2'),
  ('Jose C.A.R.P', 'Planilla 2'),
  ('Jose Moreno', 'Planilla 2'),
  ('Leonardo Lezica', 'Planilla 2'),
  ('Lucho Tato', 'Planilla 2'),
  ('Pablo Granja Lujan', 'Planilla 2'),
  ('Tato Sotelo', 'Planilla 2')
)
INSERT INTO clientes (nombre, condicion_pago, observaciones)
SELECT n.nombre, 'contado', n.planilla
  FROM nuevos n
 WHERE NOT EXISTS (SELECT 1 FROM clientes c WHERE lower(trim(c.nombre)) = lower(trim(n.nombre)));

SELECT observaciones AS planilla, count(*) AS clientes
  FROM clientes WHERE observaciones IN ('Planilla 1', 'Planilla 2')
 GROUP BY 1 ORDER BY 1;

-- ------------------------------------------------------------
-- DESPUÉS (opcional): asignar camión o lista a toda una planilla.
-- Sacale los "--" a la línea que quieras usar y cambiá el valor.
-- ------------------------------------------------------------
-- UPDATE clientes SET camion_id = (SELECT id FROM camiones WHERE numero = 'C-01') WHERE observaciones = 'Planilla 1';
-- UPDATE clientes SET camion_id = (SELECT id FROM camiones WHERE numero = 'C-02') WHERE observaciones = 'Planilla 2';
-- UPDATE clientes SET lista_precio_id = (SELECT id FROM listas_precios WHERE nombre = 'Mayorista') WHERE observaciones = 'Planilla 1';
-- UPDATE clientes SET condicion_pago = 'cta_cte' WHERE nombre IN ('Karina Pipi Cucu Cuenta', 'Carlos Raffo');
