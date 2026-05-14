-- =============================================================================
-- 05_data_quality_queries.sql  ·  Queries de calidad de datos
-- =============================================================================
-- Patrones SQL para detectar duplicados, NULLs, orphan records,
-- valores fuera de rango e inconsistencias de negocio.
-- Los mismos patrones que usan los dbt singular tests.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Unicidad de PKs
-- ─────────────────────────────────────────────────────────────────────────────
-- Un resultado vacío = sin duplicados (el check pasa).
SELECT appointment_id, COUNT(*) AS n
FROM `topd-lab.dbt_marts.fct_appointments`
GROUP BY appointment_id
HAVING n > 1;

-- Versión rápida con window function (más eficiente en tablas grandes):
SELECT appointment_id
FROM `topd-lab.dbt_marts.fct_appointments`
QUALIFY COUNT(*) OVER (PARTITION BY appointment_id) > 1;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Integridad referencial
-- ─────────────────────────────────────────────────────────────────────────────
-- Citas con patient_id que no existe en dim_patients:
SELECT a.appointment_id, a.patient_id
FROM `topd-lab.dbt_marts.fct_appointments` AS a
LEFT JOIN `topd-lab.dbt_marts.dim_patients` AS p USING (patient_id)
WHERE p.patient_id IS NULL;

-- Pagos sin cita correspondiente:
SELECT pay.payment_id, pay.appointment_id
FROM `topd-lab.dbt_marts.fct_payments` AS pay
LEFT JOIN `topd-lab.dbt_marts.fct_appointments` AS a USING (appointment_id)
WHERE a.appointment_id IS NULL;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Valores aceptados
-- ─────────────────────────────────────────────────────────────────────────────
SELECT DISTINCT status
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status NOT IN ('completed', 'cancelled', 'no_show', 'scheduled');

SELECT DISTINCT payment_status
FROM `topd-lab.dbt_marts.fct_payments`
WHERE payment_status NOT IN ('paid', 'refunded', 'failed', 'pending');


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Rangos y coherencia temporal
-- ─────────────────────────────────────────────────────────────────────────────
-- amount_cents debe ser positivo:
SELECT payment_id, amount_cents
FROM `topd-lab.dbt_marts.fct_payments`
WHERE amount_cents <= 0;

-- appointment_created_at debe ser anterior a appointment_start_at:
SELECT appointment_id, appointment_created_at, appointment_start_at
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_created_at >= appointment_start_at;

-- Pagos no deben tener fecha anterior a la cita:
SELECT p.payment_id, p.payment_created_at, a.appointment_start_at
FROM `topd-lab.dbt_marts.fct_payments`    AS p
JOIN `topd-lab.dbt_marts.fct_appointments` AS a USING (appointment_id)
WHERE p.payment_created_at < a.appointment_start_at;

-- Fechas de cita fuera del rango esperado del dataset:
SELECT COUNT(*) AS out_of_range
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date < '2022-01-01'
   OR appointment_date > CURRENT_DATE();


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Reglas de negocio específicas
-- ─────────────────────────────────────────────────────────────────────────────
-- Sólo las citas 'completed' deben tener pagos:
SELECT a.appointment_id, a.status, p.payment_id
FROM `topd-lab.dbt_marts.fct_payments`     AS p
JOIN `topd-lab.dbt_marts.fct_appointments` AS a USING (appointment_id)
WHERE a.status != 'completed';

-- Leads convertidos deben tener appointment_id válido:
SELECT lead_id, converted_appointment_id
FROM `topd-lab.dbt_marts.fct_leads` AS l
LEFT JOIN `topd-lab.dbt_marts.fct_appointments` AS a
    ON l.converted_appointment_id = a.appointment_id
WHERE l.is_converted_to_appointment = TRUE
  AND a.appointment_id IS NULL;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Distribución de NULLs por columna (auditoría rápida)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    COUNTIF(patient_id           IS NULL) AS null_patient_id,
    COUNTIF(doctor_id            IS NULL) AS null_doctor_id,
    COUNTIF(appointment_date     IS NULL) AS null_appointment_date,
    COUNTIF(status               IS NULL) AS null_status,
    COUNTIF(cancellation_reason  IS NULL) AS null_cancellation_reason,
    COUNT(*)                              AS total_rows
FROM `topd-lab.dbt_marts.fct_appointments`;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Análisis de cohortes: retención de pacientes
-- ─────────────────────────────────────────────────────────────────────────────
WITH patient_cohorts AS (
    SELECT
        patient_id,
        DATE_TRUNC(MIN(appointment_date), MONTH)  AS cohort_month
    FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE status = 'completed'
    GROUP BY patient_id
),
patient_activity AS (
    SELECT patient_id, DATE_TRUNC(appointment_date, MONTH) AS activity_month
    FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE status = 'completed'
    GROUP BY patient_id, activity_month
),
cohort_data AS (
    SELECT
        c.patient_id,
        c.cohort_month,
        DATE_DIFF(a.activity_month, c.cohort_month, MONTH) AS months_since_acquisition
    FROM patient_cohorts  AS c
    JOIN patient_activity AS a USING (patient_id)
    WHERE a.activity_month >= c.cohort_month
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT patient_id) AS cohort_size
    FROM patient_cohorts
    GROUP BY cohort_month
)
SELECT
    cd.cohort_month,
    cd.months_since_acquisition,
    cs.cohort_size,
    COUNT(DISTINCT cd.patient_id)           AS retained_patients,
    SAFE_DIVIDE(
        COUNT(DISTINCT cd.patient_id),
        cs.cohort_size
    )                                       AS retention_rate
FROM cohort_data      AS cd
JOIN cohort_sizes     AS cs USING (cohort_month)
GROUP BY cd.cohort_month, cd.months_since_acquisition, cs.cohort_size
ORDER BY cd.cohort_month, cd.months_since_acquisition;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. MoM growth del revenue
-- ─────────────────────────────────────────────────────────────────────────────
WITH monthly AS (
    SELECT
        DATE_TRUNC(payment_date, MONTH)  AS month,
        SUM(amount_eur)                  AS revenue_eur
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY month
)
SELECT
    month,
    revenue_eur,
    LAG(revenue_eur) OVER (ORDER BY month)  AS prev_month_revenue,
    ROUND(100.0 * SAFE_DIVIDE(
        revenue_eur - LAG(revenue_eur) OVER (ORDER BY month),
        LAG(revenue_eur) OVER (ORDER BY month)
    ), 2)                                   AS mom_growth_pct
FROM monthly
ORDER BY month;
