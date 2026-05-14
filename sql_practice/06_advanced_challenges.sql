-- =============================================================================
-- 06_advanced_challenges.sql  ·  Retos SQL avanzados
-- =============================================================================
-- Queries complejas que combinan múltiples técnicas: window functions,
-- CTEs encadenadas, aggregation avanzada y análisis de funnels.
-- =============================================================================

-- 1. Médico con más ingresos en cada especialidad
-- Trampa habitual: GROUP BY + MAX no da el doctor_id correcto.
-- Solución: QUALIFY con RANK.
WITH doctor_revenue AS (
    SELECT
        p.doctor_id,
        d.full_name,
        d.specialty_id,
        s.specialty_name,
        SUM(p.amount_eur)  AS total_revenue_eur
    FROM `topd-lab.dbt_marts.fct_payments`        AS p
    JOIN `topd-lab.dbt_marts.dim_doctors`         AS d USING (doctor_id)
    JOIN `topd-lab.dbt_marts.dim_specialties`     AS s USING (specialty_id)
    WHERE p.payment_status = 'paid'
    GROUP BY p.doctor_id, d.full_name, d.specialty_id, s.specialty_name
)
SELECT specialty_id, specialty_name, doctor_id, full_name, total_revenue_eur
FROM doctor_revenue
QUALIFY RANK() OVER (PARTITION BY specialty_id ORDER BY total_revenue_eur DESC) = 1;


-- 2. Segundo médico más activo de cada país (variante N-ésimo mayor)
WITH doctor_activity AS (
    SELECT doctor_id, country_id, COUNT(*) AS total_appointments
    FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE status = 'completed'
    GROUP BY doctor_id, country_id
)
SELECT country_id, doctor_id, total_appointments
FROM doctor_activity
QUALIFY DENSE_RANK() OVER (PARTITION BY country_id ORDER BY total_appointments DESC) = 2
ORDER BY country_id;


-- 3. Pacientes activos en enero que no tuvieron cita en febrero
WITH january AS (
    SELECT DISTINCT patient_id FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE appointment_date BETWEEN '2024-01-01' AND '2024-01-31'
      AND status = 'completed'
),
february AS (
    SELECT DISTINCT patient_id FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE appointment_date BETWEEN '2024-02-01' AND '2024-02-28'
      AND status = 'completed'
)
SELECT j.patient_id
FROM january AS j
WHERE NOT EXISTS (SELECT 1 FROM february AS f WHERE f.patient_id = j.patient_id);


-- 4. % que cada canal representa del total de citas
SELECT
    channel,
    COUNT(*)                                            AS appointments,
    SUM(COUNT(*)) OVER ()                               AS total_appointments,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM `topd-lab.dbt_marts.fct_appointments`
GROUP BY channel
ORDER BY appointments DESC;


-- 5. Funnel completo: lead → cita → pago
WITH funnel AS (
    SELECT
        DATE_TRUNC(created_at, MONTH)           AS month,
        COUNT(*)                                AS total_leads,
        COUNTIF(lead_status = 'converted')      AS converted_leads
    FROM `topd-lab.dbt_marts.fct_leads`
    GROUP BY month
),
payments_per_month AS (
    SELECT
        DATE_TRUNC(payment_date, MONTH)         AS month,
        COUNTIF(payment_status = 'paid')        AS paid_appointments
    FROM `topd-lab.dbt_marts.fct_payments`
    GROUP BY month
)
SELECT
    f.month,
    f.total_leads,
    f.converted_leads,
    p.paid_appointments,
    SAFE_DIVIDE(f.converted_leads, f.total_leads)        AS lead_to_appt_rate,
    SAFE_DIVIDE(p.paid_appointments, f.converted_leads)  AS appt_to_payment_rate,
    SAFE_DIVIDE(p.paid_appointments, f.total_leads)      AS end_to_end_rate
FROM funnel AS f
LEFT JOIN payments_per_month AS p USING (month)
ORDER BY f.month;


-- 6. Pacientes que volvieron dentro de los 90 días de su primera cita
WITH first_appointments AS (
    SELECT patient_id, MIN(appointment_date) AS first_date
    FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE status = 'completed'
    GROUP BY patient_id
),
has_return AS (
    SELECT
        f.patient_id,
        f.first_date,
        MIN(a.appointment_date)     AS second_date,
        DATE_DIFF(
            MIN(a.appointment_date), f.first_date, DAY
        ) <= 90                     AS returned_within_90_days
    FROM first_appointments AS f
    LEFT JOIN `topd-lab.dbt_marts.fct_appointments` AS a
        ON  a.patient_id     = f.patient_id
        AND a.appointment_date > f.first_date
        AND a.status         = 'completed'
    GROUP BY f.patient_id, f.first_date
)
SELECT
    DATE_TRUNC(first_date, MONTH)               AS acquisition_month,
    COUNT(*)                                    AS new_patients,
    COUNTIF(returned_within_90_days = TRUE)     AS returned_in_90d,
    SAFE_DIVIDE(
        COUNTIF(returned_within_90_days = TRUE), COUNT(*)
    )                                           AS return_rate
FROM has_return
GROUP BY acquisition_month
ORDER BY acquisition_month;


-- 7. Días desde la última cita por paciente + segmento de actividad
SELECT DISTINCT
    patient_id,
    MAX(appointment_date) OVER (PARTITION BY patient_id) AS last_appointment_date,
    DATE_DIFF(
        CURRENT_DATE(),
        MAX(appointment_date) OVER (PARTITION BY patient_id),
        DAY
    )                                                    AS days_since_last_visit,
    CASE
        WHEN DATE_DIFF(CURRENT_DATE(),
             MAX(appointment_date) OVER (PARTITION BY patient_id), DAY) <= 90
             THEN 'active'
        WHEN DATE_DIFF(CURRENT_DATE(),
             MAX(appointment_date) OVER (PARTITION BY patient_id), DAY) <= 365
             THEN 'at_risk'
        ELSE 'churned'
    END                                                  AS patient_segment
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed'
ORDER BY days_since_last_visit DESC;


-- 8. % de cada médico sobre el revenue total de su especialidad
WITH doctor_completed AS (
    SELECT doctor_id, specialty_id,
           COUNTIF(status = 'completed') AS doc_completed
    FROM `topd-lab.dbt_marts.fct_appointments`
    GROUP BY doctor_id, specialty_id
),
specialty_total AS (
    SELECT specialty_id,
           COUNTIF(status = 'completed') AS spec_completed
    FROM `topd-lab.dbt_marts.fct_appointments`
    GROUP BY specialty_id
)
SELECT
    d.doctor_id,
    d.specialty_id,
    d.doc_completed,
    s.spec_completed,
    SAFE_DIVIDE(d.doc_completed, s.spec_completed) AS pct_of_specialty
FROM doctor_completed AS d
JOIN specialty_total  AS s USING (specialty_id)
ORDER BY pct_of_specialty DESC;
