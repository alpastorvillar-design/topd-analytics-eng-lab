-- =============================================================================
-- 01_joins.sql  ·  JOINs en BigQuery
-- =============================================================================
-- Patrones de JOIN aplicados al modelo de datos de MediConnect.
-- Sustituye `project.dataset` por tu proyecto real.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TIPOS DE JOIN
-- INNER JOIN  → sólo filas con coincidencia en ambas tablas
-- LEFT JOIN   → todas las filas de la izquierda + coincidencias (NULL si no hay)
-- FULL OUTER  → todas las filas de ambas tablas
-- CROSS JOIN  → producto cartesiano
-- BigQuery y PostgreSQL comparten la misma sintaxis.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. INNER JOIN: citas con nombre de paciente y médico
SELECT
    a.appointment_id,
    a.appointment_start_at,
    a.status,
    p.full_name   AS patient_name,
    d.full_name   AS doctor_name
FROM `project.dbt_marts.fct_appointments`    AS a
INNER JOIN `project.dbt_marts.dim_patients`  AS p USING (patient_id)
INNER JOIN `project.dbt_marts.dim_doctors`   AS d USING (doctor_id)
WHERE a.appointment_date >= '2023-01-01'
LIMIT 100;


-- 2. LEFT JOIN: médicos con nº de citas completadas (incluye médicos con 0)
-- La condición de status va en ON, no en WHERE.
-- WHERE a.status = 'completed' convertiría el LEFT en INNER (filtraría NULLs).
SELECT
    d.doctor_id,
    d.full_name,
    d.specialty_id,
    COUNT(a.appointment_id)  AS completed_appointments
FROM `project.dbt_marts.dim_doctors` AS d
LEFT JOIN `project.dbt_marts.fct_appointments` AS a
    ON  d.doctor_id = a.doctor_id
    AND a.status    = 'completed'
GROUP BY d.doctor_id, d.full_name, d.specialty_id
ORDER BY completed_appointments DESC;


-- 3. Anti-join: pagos sin cita correspondiente (detección de huérfanos)
SELECT
    pay.payment_id,
    pay.appointment_id,
    pay.amount_cents
FROM `project.dbt_marts.fct_payments` AS pay
LEFT JOIN `project.dbt_marts.fct_appointments` AS a
    USING (appointment_id)
WHERE a.appointment_id IS NULL;


-- 4. FULL OUTER JOIN: unir métricas de appointments y payments por día
-- Hay días con citas pero sin pagos (no_show/cancelled) y viceversa.
WITH daily_appts AS (
    SELECT
        appointment_date               AS date,
        COUNT(*)                       AS total_appointments
    FROM `project.dbt_marts.fct_appointments`
    GROUP BY appointment_date
),
daily_payments AS (
    SELECT
        payment_date                   AS date,
        SUM(amount_eur)                AS total_revenue_eur
    FROM `project.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY payment_date
)
SELECT
    COALESCE(a.date, p.date)           AS date,
    COALESCE(a.total_appointments, 0)  AS total_appointments,
    COALESCE(p.total_revenue_eur, 0)   AS total_revenue_eur
FROM daily_appts    AS a
FULL OUTER JOIN daily_payments AS p USING (date)
ORDER BY date;


-- 5. SELF JOIN: pacientes que visitaron al mismo médico más de una vez
SELECT
    a1.patient_id,
    a1.doctor_id,
    a1.appointment_id       AS first_visit,
    a2.appointment_id       AS repeat_visit,
    a1.appointment_start_at AS first_date,
    a2.appointment_start_at AS repeat_date
FROM `project.dbt_marts.fct_appointments` AS a1
JOIN `project.dbt_marts.fct_appointments` AS a2
    ON  a1.patient_id = a2.patient_id
    AND a1.doctor_id  = a2.doctor_id
    AND a1.appointment_start_at < a2.appointment_start_at
WHERE a1.status = 'completed'
  AND a2.status = 'completed'
ORDER BY a1.patient_id, first_date;


-- 6. JOIN con enriquecimiento dimensional: revenue por especialidad y país
SELECT
    s.specialty_name,
    c.country_name,
    COUNT(DISTINCT a.patient_id)        AS unique_patients,
    COUNT(a.appointment_id)             AS total_appointments,
    ROUND(SUM(p.amount_eur), 2)         AS total_revenue_eur,
    SAFE_DIVIDE(
        SUM(p.amount_eur),
        COUNT(DISTINCT a.patient_id)
    )                                   AS revenue_per_patient
FROM `project.dbt_marts.fct_appointments`   AS a
JOIN `project.dbt_marts.fct_payments`       AS p   USING (appointment_id)
JOIN `project.dbt_marts.dim_specialties`    AS s   USING (specialty_id)
JOIN `project.dbt_marts.dim_countries`      AS c   ON c.country_id = a.country_id
WHERE p.payment_status = 'paid'
GROUP BY s.specialty_name, c.country_name
ORDER BY total_revenue_eur DESC;
