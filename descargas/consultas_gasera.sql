-- Consultas de análisis para el sistema de puntos de la gasera (MySQL 8)
-- Tablas: customers, purchases, reward_transactions   |   Fecha de corte usada en 4: '2026-10-20'

-- 1) Ventas por mes: litros, compras, cancelaciones y tasa de cancelación
SELECT DATE_FORMAT(p.createdAt, '%Y-%m')                                         AS mes,
       COUNT(*)                                                                  AS compras,
       SUM(p.status = 'CANCELED')                                                AS canceladas,
       ROUND(100 * SUM(p.status = 'CANCELED') / COUNT(*), 2)                     AS pct_cancelacion,
       ROUND(SUM(CASE WHEN p.status = 'ACTIVE' THEN p.liters ELSE 0 END), 2)     AS litros_vendidos
FROM purchases p
GROUP BY mes
ORDER BY mes;

-- 2) Economía de puntos por mes: emitidos vs canjeados y tasa de canje
SELECT DATE_FORMAT(rt.createdAt, '%Y-%m')                                        AS mes,
       ROUND(SUM(CASE WHEN rt.type = 'EARNED'   THEN rt.points ELSE 0 END), 2)   AS puntos_emitidos,
       ROUND(SUM(CASE WHEN rt.type = 'REDEEMED' THEN rt.points ELSE 0 END), 2)   AS puntos_canjeados,
       ROUND(100 * SUM(CASE WHEN rt.type = 'REDEEMED' THEN rt.points ELSE 0 END)
                 / NULLIF(SUM(CASE WHEN rt.type = 'EARNED' THEN rt.points ELSE 0 END), 0), 2) AS tasa_canje_pct
FROM reward_transactions rt
GROUP BY mes
ORDER BY mes;

-- 3) Conciliación: saldo almacenado vs saldo recalculado desde el ledger (EARNED - REDEEMED + ADJUSTMENT)
SELECT c.id, c.user, c.name,
       c.points                                                                  AS saldo_almacenado,
       ROUND(COALESCE(SUM(CASE rt.type WHEN 'REDEEMED' THEN -rt.points ELSE rt.points END), 0), 2) AS saldo_ledger,
       ROUND(c.points - COALESCE(SUM(CASE rt.type WHEN 'REDEEMED' THEN -rt.points ELSE rt.points END), 0), 2) AS diferencia
FROM customers c
LEFT JOIN reward_transactions rt ON rt.customer_id = c.id
WHERE c.role = 'USER'
GROUP BY c.id, c.user, c.name, c.points
HAVING ABS(diferencia) > 0.005
ORDER BY ABS(diferencia) DESC;

-- 4) Clientes inactivos: días desde su última compra activa y bucket 30 / 60 / 90
SELECT c.id, c.user, c.name,
       MAX(p.createdAt)                                                          AS ultima_compra,
       DATEDIFF('2026-10-20', MAX(p.createdAt))                                  AS dias_sin_comprar,
       CASE WHEN DATEDIFF('2026-10-20', MAX(p.createdAt)) > 90 THEN '90+'
            WHEN DATEDIFF('2026-10-20', MAX(p.createdAt)) > 60 THEN '61-90'
            WHEN DATEDIFF('2026-10-20', MAX(p.createdAt)) > 30 THEN '31-60'
            ELSE 'activo (<=30)' END                                             AS bucket
FROM customers c
JOIN purchases p ON p.customer_id = c.id AND p.status = 'ACTIVE'
WHERE c.role = 'USER' AND c.active = 1
GROUP BY c.id, c.user, c.name
ORDER BY dias_sin_comprar DESC;

-- 5) Pareto de clientes: litros por cliente y porcentaje acumulado (ventana)
SELECT t.user, t.name, t.litros,
       ROUND(100 * SUM(t.litros) OVER (ORDER BY t.litros DESC, t.id) / SUM(t.litros) OVER (), 2) AS pct_acumulado
FROM (SELECT c.id, c.user, c.name, SUM(p.liters) AS litros
      FROM customers c JOIN purchases p ON p.customer_id = c.id AND p.status = 'ACTIVE'
      WHERE c.role = 'USER'
      GROUP BY c.id, c.user, c.name) t
ORDER BY t.litros DESC;
