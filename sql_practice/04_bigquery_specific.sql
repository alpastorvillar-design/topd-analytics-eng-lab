-- =============================================================================
-- 04_bigquery_specific.sql  ·  BigQuery vs PostgreSQL
-- =============================================================================
-- COUNTIF, SAFE_DIVIDE, QUALIFY, DATE_TRUNC/DIFF, GENERATE_DATE_ARRAY,
-- UNNEST, partition pruning, IF, FORMAT_DATE — equivalentes PG incluidos.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. COUNTIF  (BigQuery) vs  COUNT FILTER  (PostgreSQL)
-- ─────────────────────────────────────────────────────────────────────────────
-- BigQuery:
SELECT
    DATE_TRUNC(appointment_date, MONTH)         AS month,
    COUNTIF(status = 'completed')               AS completed,
    COUNTIF(status = 'no_show')                 AS no_show,
    COUNTIF(is_first_appointment = TRUE)        AS new_patients
FROM `topd-lab.dbt_marts.fct_appointments`
GROUP BY month;

-- PostgreSQL equivalente:
-- COUNT(*) FILTER (WHERE status = 'completed')
-- O también: COUNT(CASE WHEN status = 'completed' THEN 1 END)


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. SAFE_DIVIDE  (BigQuery) vs  / NULLIF  (PostgreSQL)
-- ─────────────────────────────────────────────────────────────────────────────
-- BigQuery devuelve NULL si el denominador es 0 (no error):
SELECT
    specialty_id,
    COUNT(*)                                    AS total_appointments,
    COUNTIF(status = 'completed')               AS completed,
    SAFE_DIVIDE(
        COUNTIF(status = 'completed'), COUNT(*)
    )                                           AS completion_rate
FROM `topd-lab.dbt_marts.fct_appointments`
GROUP BY specialty_id;

-- PostgreSQL:  completed::numeric / NULLIF(total, 0)


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. QUALIFY: filtrar por window function sin subquery
-- ─────────────────────────────────────────────────────────────────────────────
-- El médico top por revenue en cada especialidad:
WITH doctor_rev AS (
    SELECT
        d.doctor_id,
        d.specialty_id,
        SUM(p.amount_eur) AS revenue_eur
    FROM `topd-lab.dbt_marts.fct_payments`  AS p
    JOIN `topd-lab.dbt_marts.dim_doctors`   AS d USING (doctor_id)
    WHERE p.payment_status = 'paid'
    GROUP BY d.doctor_id, d.specialty_id
)
SELECT specialty_id, doctor_id, revenue_eur
FROM doctor_rev
QUALIFY RANK() OVER (PARTITION BY specialty_id ORDER BY revenue_eur DESC) = 1;

-- PostgreSQL necesita una subquery o CTE extra:
-- SELECT * FROM (SELECT ..., RANK() OVER (...) AS rnk FROM doctor_rev) WHERE rnk = 1


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. DATE_TRUNC y DATE_DIFF
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    appointment_id,
    appointment_date,
    DATE_TRUNC(appointment_date, MONTH)     AS month,
    DATE_TRUNC(appointment_date, YEAR)      AS year,
    -- DATE_DIFF(end, start, unit)
    DATE_DIFF(CURRENT_DATE(), appointment_date, DAY)    AS days_ago,
    DATE_DIFF(CURRENT_DATE(), appointment_date, MONTH)  AS months_ago
FROM `topd-lab.dbt_marts.fct_appointments`
LIMIT 10;

-- PostgreSQL:
-- DATE_TRUNC('month', appointment_date)  -- mismo nombre, parámetro como string
-- (CURRENT_DATE - appointment_date)      -- devuelve interval, no integer


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. GENERATE_DATE_ARRAY y UNNEST
-- ─────────────────────────────────────────────────────────────────────────────
-- Generar un rango de fechas sin CTE recursiva:
SELECT date
FROM UNNEST(
    GENERATE_DATE_ARRAY('2023-01-01', '2023-12-31', INTERVAL 1 MONTH)
) AS date;

-- UNNEST también expande arrays a filas:
SELECT name, tag
FROM `topd-lab.dbt_marts.dim_doctors`
CROSS JOIN UNNEST(tags) AS tag   -- si tags fuera un campo ARRAY<STRING>
WHERE tags IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Particionamiento y clustering: cómo afectan a los queries
-- ─────────────────────────────────────────────────────────────────────────────
-- fct_appointments está particionada por appointment_date (MONTH)
-- y tiene clustering en [country_id, specialty_id, status].

-- Esta query sólo escanea las particiones de 2024 → menos bytes → menor coste:
SELECT COUNT(*), SUM(amount_eur)
FROM `topd-lab.dbt_marts.fct_payments`
WHERE payment_date >= '2024-01-01'          -- partition pruning
  AND country_id = 'ES'                     -- clustering benefit
  AND payment_status = 'paid';

-- Para ver cuántos bytes escanea una query: usa "Ejecutar → Bytes procesados"
-- en BigQuery Console antes de ejecutar con CTRL+Mayús para ver el estimado.


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. IF y CASE: expresiones condicionales
-- ─────────────────────────────────────────────────────────────────────────────
-- IF(condición, valor_si_true, valor_si_false) — sólo BigQuery
SELECT
    appointment_id,
    status,
    IF(status = 'completed', 'Exitosa', 'No completada')    AS outcome,
    CASE status
        WHEN 'completed' THEN 'Exitosa'
        WHEN 'cancelled' THEN 'Cancelada'
        WHEN 'no_show'   THEN 'No se presentó'
        ELSE 'Pendiente'
    END                                                     AS outcome_label,
    -- Pivot manual con IF:
    IF(status = 'completed', amount_eur, 0)                 AS revenue_if_completed
FROM `topd-lab.dbt_marts.fct_appointments`
LEFT JOIN `topd-lab.dbt_marts.fct_payments` USING (appointment_id)
LIMIT 20;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. FORMAT_DATE y PARSE_DATE
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    appointment_date,
    FORMAT_DATE('%Y-%m', appointment_date)      AS year_month_str,   -- '2023-06'
    FORMAT_DATE('%B %Y', appointment_date)      AS month_name,       -- 'June 2023'
    FORMAT_DATE('%Q', appointment_date)         AS quarter_number,   -- '2'
    CONCAT('Q', FORMAT_DATE('%Q', appointment_date),
           '-', FORMAT_DATE('%Y', appointment_date)) AS quarter_label -- 'Q2-2023'
FROM `topd-lab.dbt_marts.fct_appointments`
LIMIT 5;
