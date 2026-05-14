-- =============================================================================
-- 03_window_functions.sql  ·  Window Functions
-- =============================================================================
-- ROW_NUMBER / RANK / DENSE_RANK, LAG/LEAD, SUM OVER frames, FIRST/LAST_VALUE,
-- NTILE, QUALIFY. Sin colapsar filas, a diferencia de GROUP BY.
-- =============================================================================

-- 1. ROW_NUMBER: numerar visitas de cada paciente por fecha
SELECT
    patient_id,
    appointment_id,
    appointment_start_at,
    status,
    ROW_NUMBER() OVER (
        PARTITION BY patient_id
        ORDER BY appointment_start_at
    )                                       AS visit_number
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed'
ORDER BY patient_id, visit_number;


-- 2. RANK vs DENSE_RANK vs ROW_NUMBER
-- Con empates:  ROW_NUMBER → 1,2,3,4 (siempre único)
--               RANK       → 1,2,2,4 (salta número)
--               DENSE_RANK → 1,2,2,3 (sin salto)
SELECT
    specialty_id,
    month,
    total_revenue_eur,
    RANK()       OVER (PARTITION BY month ORDER BY total_revenue_eur DESC) AS rnk,
    DENSE_RANK() OVER (PARTITION BY month ORDER BY total_revenue_eur DESC) AS dense_rnk,
    ROW_NUMBER() OVER (PARTITION BY month ORDER BY total_revenue_eur DESC) AS row_num
FROM `topd-lab.dbt_marts.agg_specialty_performance`
ORDER BY month, rnk;


-- 3. LAG / LEAD: días entre citas consecutivas del mismo paciente
SELECT
    patient_id,
    appointment_id,
    appointment_start_at                                    AS current_appt,
    LAG(appointment_start_at) OVER (
        PARTITION BY patient_id
        ORDER BY appointment_start_at
    )                                                       AS previous_appt,
    DATE_DIFF(
        DATE(appointment_start_at),
        DATE(LAG(appointment_start_at) OVER (
            PARTITION BY patient_id
            ORDER BY appointment_start_at
        )),
        DAY
    )                                                       AS days_since_last_visit
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed'
ORDER BY patient_id, current_appt;


-- 4. SUM OVER: revenue acumulado (running total) y ventana rolling 7 días
WITH daily AS (
    SELECT payment_date, SUM(amount_eur) AS daily_revenue
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY payment_date
)
SELECT
    payment_date,
    daily_revenue,
    SUM(daily_revenue) OVER (
        ORDER BY payment_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                        AS cumulative_revenue,
    SUM(daily_revenue) OVER (
        ORDER BY payment_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )                        AS revenue_last_7_days
FROM daily
ORDER BY payment_date;


-- 5. FIRST_VALUE / LAST_VALUE: primera y última cita de cada paciente
-- LAST_VALUE necesita frame explícito; sin él usa RANGE BETWEEN UNBOUNDED
-- PRECEDING AND CURRENT ROW y devuelve la fila actual, no la última.
SELECT DISTINCT
    patient_id,
    FIRST_VALUE(appointment_id) OVER (
        PARTITION BY patient_id
        ORDER BY appointment_start_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                           AS first_appointment_id,
    LAST_VALUE(appointment_id) OVER (
        PARTITION BY patient_id
        ORDER BY appointment_start_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    )                           AS last_appointment_id
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed';


-- 6. NTILE: segmentar médicos en cuartiles por revenue
WITH doctor_revenue AS (
    SELECT doctor_id, SUM(amount_eur) AS total_revenue
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY doctor_id
)
SELECT
    doctor_id,
    total_revenue,
    NTILE(4) OVER (ORDER BY total_revenue DESC)  AS revenue_quartile
    -- 1 = top 25%, 4 = bottom 25%
FROM doctor_revenue
ORDER BY revenue_quartile, total_revenue DESC;


-- 7. QUALIFY: filtrar por window function sin subquery (BigQuery / Snowflake)
-- Equivalente PostgreSQL requiere subquery o CTE.

-- Cita más reciente de cada paciente:
SELECT patient_id, appointment_id, appointment_start_at, status
FROM `topd-lab.dbt_marts.fct_appointments`
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY patient_id
    ORDER BY appointment_start_at DESC
) = 1;

-- % del total por canal usando SUM OVER sin PARTITION BY:
SELECT
    channel,
    COUNT(*)                                        AS appointments,
    SUM(COUNT(*)) OVER ()                           AS total_appointments,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM `topd-lab.dbt_marts.fct_appointments`
GROUP BY channel
ORDER BY appointments DESC;
