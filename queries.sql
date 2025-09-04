1️⃣ Listar los productos con stock menor a 5 unidades.


SELECT id, nombre
FROM productos
WHERE stock < 5;

2️⃣ Calcular ventas totales de un mes específico.

SELECT  COUNT(id) AS total_ventas
FROM ventas
WHERE EXTRACT (MONTH FROM fecha)  = 9;

3️⃣ Obtener el cliente con más compras realizadas.

SELECT c.id, c.nombre AS cliente_mas_compras, COUNT(v.id) AS total_compras
FROM ventas AS v
JOIN clientes c ON v.cliente_id = c.id
GROUP BY c.id, c.nombre
ORDER BY total_compras DESC
LIMIT 1;

4️⃣ Listar los 5 productos más vendidos.

SELECT p.id, p.nombre, SUM(vd.cantidad) AS total_vendido
FROM ventas_detalles AS vd
JOIN productos p ON vd.producto_id = p.id
GROUP BY p.id, p.nombre
ORDER BY total_vendido DESC
LIMIT 5;

5️⃣ Consultar ventas realizadas en un rango de fechas de tres Días y un Mes.

SELECT v.id AS ventas_realizadas
FROM ventas AS v
WHERE v.fecha >= '2025-08-01'
  AND v.fecha <  '2025-09-01';

6️⃣ Identificar clientes que no han comprado en los últimos 6 meses.

SELECT c.id, c.nombre
FROM clientes AS c
LEFT JOIN ventas AS v ON v.cliente_id = c.id
  AND v.fecha >= CURRENT_DATE - INTERVAL '6 months'
WHERE v.id IS NULL;
