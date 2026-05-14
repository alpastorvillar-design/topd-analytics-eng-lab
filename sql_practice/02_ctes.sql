-- =============================================================================
-- 02_ctes.sql  ·  CTEs y subqueries
-- =============================================================================
-- CTE vs subquery anidada, CTEs encadenadas (patrón dbt), NOT EXISTS,
-- series de fechas con GENERATE_DATE_ARRAY, QUALIFY con subquery inline.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- CTE vs subquery
-- ─────────────────────────────────────────────────────────────────────────────

-- Con subquery anidada (difícil de mantener):
SELECT doctor_id, total_revenue
FROM (
    SELECT doctor_id, SUM(amount_eur) AS total_revenue
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY doctor_id
)
WHERE total_revenue > 5000;

-- Con CTE (mismo resultado, más legible):
WITH doctor_revenue AS (
    SELECT
        doctor_id,
        SUM(amount_eur)  AS total_revenue
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY doctor_id
)
SELECT doctor_id, total_revenue
FROM doctor_revenue
WHERE total_revenue > 5000
ORDER BY total_revenue DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- CTEs encadenadas: pipeline de transformaciones (patrón dbt)
-- ─────────────────────────────────────────────────────────────────────────────
WITH

appointments_enriched AS (
    SELECT
        a.appointment_id,
        a.patient_id,
        a.doctor_id,
        a.appointment_date,
        a.specialty_id,
        a.country_id,
        a.channel,
        p.full_name      AS patient_name,
        d.full_name      AS doctor_name,
        s.specialty_name
    FROM `topd-lab.dbt_marts.fct_appointments`   AS a
    JOIN `topd-lab.dbt_marts.dim_patients`       AS p USING (patient_id)
    JOIN `topd-lab.dbt_marts.dim_doctors`        AS d USING (doctor_id)
    JOIN `topd-lab.dbt_marts.dim_specialties`    AS s USING (specialty_id)
    WHERE a.status = 'completed'
),

doctor_specialty_summary AS (
    SELECT
        doctor_id,
        doctor_name,
        specialty_name,
        COUNT(*)                        AS completed_appointments,
        COUNT(DISTINCT patient_id)      AS unique_patients,
        COUNT(DISTINCT appointment_date) AS active_days
    FROM appointments_enriched
    GROUP BY doctor_id, doctor_name, specialty_name
),

doctor_revenue AS (
    SELECT
        a.doctor_id,
        SUM(p.amount_eur)               AS total_revenue_eur
    FROM appointments_enriched          AS a
    JOIN `topd-lab.dbt_marts.fct_payments` AS p USING (appointment_id)
    WHERE p.payment_status = 'paid'
    GROUP BY a.doctor_id
)

SELECT
    s.doctor_id,
    s.doctor_name,
    s.specialty_name,
    s.completed_appointments,
    s.unique_patients,
    s.active_days,
    COALESCE(r.total_revenue_eur, 0)    AS total_revenue_eur,
    SAFE_DIVIDE(
        COALESCE(r.total_revenue_eur, 0),
        s.completed_appointments
    )                                   AS avg_revenue_per_appointment
FROM doctor_specialty_summary   AS s
LEFT JOIN doctor_revenue        AS r USING (doctor_id)
ORDER BY total_revenue_eur DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- NOT EXISTS: más robusto que NOT IN cuando puede haber NULLs
-- ─────────────────────────────────────────────────────────────────────────────
-- NOT IN devuelve 0 filas si la subquery contiene algún NULL.
-- NOT EXISTS es seguro con NULLs y generalmente más eficiente.

-- Pacientes que nunca han completado una cita:
SELECT patient_id, full_name
FROM `topd-lab.dbt_marts.dim_patients`
WHERE NOT EXISTS (
    SELECT 1
    FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE fct_appointments.patient_id = dim_patients.patient_id
      AND status = 'completed'
);


-- ─────────────────────────────────────────────────────────────────────────────
-- Generar serie de fechas (dos enfoques)
-- ─────────────────────────────────────────────────────────────────────────────

-- Opción A: CTE recursiva (compatible con PostgreSQL)
WITH RECURSIVE date_series AS (
    SELECT DATE '2023-01-01' AS d
    UNION ALL
    SELECT DATE_ADD(d, INTERVAL 1 DAY)
    FROM date_series
    WHERE d < DATE '2023-01-31'
)
SELECT d FROM date_series;

-- Opción B: GENERATE_DATE_ARRAY (BigQuery, más eficiente)
SELECT d
FROM UNNEST(
    GENERATE_DATE_ARRAY('2023-01-01', '2023-12-31', INTERVAL 1 DAY)
) AS d;

-- Uso práctico: asegurar fila por día aunque no haya revenue ese día
WITH all_dates AS (
    SELECT d AS date
    FROM UNNEST(GENERATE_DATE_ARRAY('2023-01-01', '2023-12-31', INTERVAL 1 DAY)) AS d
),
daily_revenue AS (
    SELECT payment_date, SUM(amount_eur) AS revenue_eur
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY payment_date
)
SELECT
    d.date,
    COALESCE(r.revenue_eur, 0)  AS revenue_eur
FROM all_dates AS d
LEFT JOIN daily_revenue AS r ON d.date = r.payment_date
ORDER BY d.date;


-- ─────────────────────────────────────────────────────────────────────────────
-- Canal con más no-shows por especialidad (QUALIFY + subquery inline)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    specialty_id,
    channel,
    no_show_count,
    total_count,
    SAFE_DIVIDE(no_show_count, total_count) AS no_show_rate
FROM (
    SELECT
        specialty_id,
        channel,
        COUNTIF(status = 'no_show')         AS no_show_count,
        COUNT(*)                            AS total_count
    FROM `topd-lab.dbt_marts.fct_appointments`
    GROUP BY specialty_id, channel
)
QUALIFY RANK() OVER (
    PARTITION BY specialty_id
    ORDER BY no_show_count DESC
) = 1
ORDER BY specialty_id;
