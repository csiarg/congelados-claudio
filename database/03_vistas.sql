-- ============================================================
-- CONGELADOS CLAUDIO · Base de datos v2
-- 03_vistas.sql  →  Consultas listas para usar en pantallas
-- security_invoker: respetan los permisos del usuario que consulta.
-- Se puede volver a ejecutar.
-- ============================================================

-- Stock por producto: depósito, camiones y total
CREATE OR REPLACE VIEW v_stock WITH (security_invoker = true) AS
SELECT p.id AS producto_id, p.codigo, p.descripcion, p.marca, p.rubro, p.unidad,
       pr.nombre AS proveedor,
       COALESCE(sum(s.cantidad) FILTER (WHERE s.camion_id IS NULL), 0)     AS stock_deposito,
       COALESCE(sum(s.cantidad) FILTER (WHERE s.camion_id IS NOT NULL), 0) AS stock_camiones,
       COALESCE(sum(s.cantidad), 0)                                         AS stock_total,
       p.stock_minimo,
       (p.stock_minimo > 0 AND COALESCE(sum(s.cantidad), 0) < p.stock_minimo) AS bajo_minimo,
       p.costo_promedio, p.precio_venta,
       round(COALESCE(sum(s.cantidad), 0) * p.costo_promedio, 2)            AS valor_stock,
       p.activo
  FROM productos p
  LEFT JOIN proveedores pr ON pr.id = p.proveedor_id
  LEFT JOIN stock s ON s.producto_id = p.id
 GROUP BY p.id, pr.nombre;

-- Lo que hay arriba de cada camión
CREATE OR REPLACE VIEW v_stock_camiones WITH (security_invoker = true) AS
SELECT c.id AS camion_id, c.numero AS camion, p.id AS producto_id, p.codigo, p.descripcion,
       p.unidad, s.cantidad, round(s.cantidad * p.costo_promedio, 2) AS valor_costo,
       r.id AS recorrido_id, r.numero AS recorrido_numero
  FROM stock s
  JOIN camiones c  ON c.id = s.camion_id
  JOIN productos p ON p.id = s.producto_id
  LEFT JOIN recorridos r ON r.camion_id = c.id AND r.estado = 'en_curso'
 WHERE s.cantidad <> 0;

-- Saldo de cada cliente
CREATE OR REPLACE VIEW v_saldos WITH (security_invoker = true) AS
SELECT c.id AS cliente_id, c.codigo, c.nombre, c.localidad, c.telefono, c.whatsapp,
       c.condicion_pago, c.limite_credito, l.nombre AS lista_precio, ca.numero AS camion,
       COALESCE(sum(m.debe - m.haber), 0) AS saldo,
       max(m.fecha) AS ultimo_movimiento,
       max(m.fecha) FILTER (WHERE m.tipo = 'venta') AS ultima_compra,
       max(m.fecha) FILTER (WHERE m.tipo = 'pago')  AS ultimo_pago,
       c.activo
  FROM clientes c
  LEFT JOIN listas_precios l ON l.id = c.lista_precio_id
  LEFT JOIN camiones ca ON ca.id = c.camion_id
  LEFT JOIN cta_cte_movimientos m ON m.cliente_id = c.id
 GROUP BY c.id, l.nombre, ca.numero;

-- Resumen de cuenta corriente con saldo acumulado renglón a renglón
CREATE OR REPLACE VIEW v_cta_cte WITH (security_invoker = true) AS
SELECT m.id, m.cliente_id, c.nombre AS cliente, m.fecha, m.tipo, m.descripcion,
       m.debe, m.haber,
       sum(m.debe - m.haber) OVER (PARTITION BY m.cliente_id ORDER BY m.fecha, m.id) AS saldo,
       m.pedido_id, m.pago_id, m.devolucion_id
  FROM cta_cte_movimientos m
  JOIN clientes c ON c.id = m.cliente_id;

-- Listado de pedidos
CREATE OR REPLACE VIEW v_pedidos WITH (security_invoker = true) AS
SELECT pe.id, pe.numero, pe.fecha, pe.estado, pe.origen,
       c.id AS cliente_id, c.codigo AS cliente_codigo, c.nombre AS cliente, c.direccion, c.localidad,
       ca.numero AS camion, rep.numero AS camion_reparto,
       pe.total, pe.total - pe.costo_total AS ganancia,
       (SELECT count(*) FROM pedidos_items i WHERE i.pedido_id = pe.id) AS renglones,
       COALESCE((SELECT sum(d.total) FROM devoluciones d WHERE d.pedido_id = pe.id), 0) AS devuelto,
       pe.notas, pe.entregado_at, pe.recorrido_id
  FROM pedidos pe
  JOIN clientes c ON c.id = pe.cliente_id
  LEFT JOIN camiones ca  ON ca.id  = pe.camion_id
  LEFT JOIN camiones rep ON rep.id = pe.reparto_camion_id;

-- Detalle de renglones de pedido
CREATE OR REPLACE VIEW v_pedidos_items WITH (security_invoker = true) AS
SELECT i.id, i.pedido_id, pe.numero AS pedido_numero, p.codigo, p.descripcion, p.unidad,
       i.cantidad, i.cantidad_devuelta, i.precio_unitario, i.importe
  FROM pedidos_items i
  JOIN pedidos pe  ON pe.id = i.pedido_id
  JOIN productos p ON p.id = i.producto_id;

-- Ventas por día y camión
CREATE OR REPLACE VIEW v_ventas_diarias WITH (security_invoker = true) AS
SELECT (pe.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS dia,
       COALESCE(ca.numero, 'Depósito') AS camion,
       count(*) AS pedidos,
       sum(pe.total) AS ventas,
       sum(pe.total - pe.costo_total) AS ganancia
  FROM pedidos pe
  LEFT JOIN camiones ca ON ca.id = COALESCE(pe.camion_id, pe.reparto_camion_id)
 WHERE pe.estado <> 'cancelado'
 GROUP BY 1, 2;

-- Kardex legible
CREATE OR REPLACE VIEW v_movimientos_stock WITH (security_invoker = true) AS
SELECT m.id, m.fecha, p.codigo, p.descripcion, COALESCE('Camión ' || c.numero, 'Depósito') AS ubicacion,
       m.tipo, m.cantidad, m.saldo, m.costo_unitario, m.observacion,
       pf.nombre AS usuario, m.producto_id, m.camion_id, m.recorrido_id, m.pedido_id
  FROM movimientos_stock m
  JOIN productos p ON p.id = m.producto_id
  LEFT JOIN camiones c ON c.id = m.camion_id
  LEFT JOIN perfiles pf ON pf.user_id = m.usuario_id;
