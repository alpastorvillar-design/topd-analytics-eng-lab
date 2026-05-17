-- ad_hoc_doctor_capacity.sql
-- Exploratory analysis of doctor capacity and utilisation.

-- 1. Top 20 doctors by completed appointments
SELECT
    d.doctor_id,
    d.full_name,
    d.specialty_id,
    d.country_id,
    COUNT(a.appointment_id)              AS completed_appointments,
    COUNT(DISTINCT a.patient_id)         AS unique_patients,
    ROUND(SUM(p.amount_eur), 2)          AS total_revenue_eur,
    ROUND(AVG(d.rating), 2)             AS avg_rating
FROM {{ ref('fct_appointments') }}    AS a
JOIN {{ ref('dim_doctors') }}         AS d USING (doctor_id)
LEFT JOIN {{ ref('fct_payments') }}   AS p
    ON p.appointment_id = a.appointment_id AND p.payment_status = 'paid'
WHERE a.status = 'completed'
GROUP BY d.doctor_id, d.full_name, d.specialty_id, d.country_id
ORDER BY completed_appointments DESC
LIMIT 20;


-- 2. Revenue rank per doctor within specialty
SELECT
    d.specialty_id,
    d.doctor_id,
    d.full_name,
    SUM(p.amount_eur)                    AS revenue_eur,
    RANK() OVER (
        PARTITION BY d.specialty_id
        ORDER BY SUM(p.amount_eur) DESC
    )                                    AS revenue_rank_in_specialty
FROM {{ ref('fct_payments') }}  AS p
JOIN {{ ref('dim_doctors') }}   AS d USING (doctor_id)
WHERE p.payment_status = 'paid'
GROUP BY d.specialty_id, d.doctor_id, d.full_name
QUALIFY revenue_rank_in_specialty <= 3
ORDER BY d.specialty_id, revenue_rank_in_specialty;


-- 3. Monthly appointment volume per doctor (last 12 months of dataset)
SELECT
    DATE_TRUNC(a.appointment_date, MONTH)   AS month,
    a.doctor_id,
    COUNT(*)                                AS total_appointments,
    COUNTIF(a.status = 'completed')         AS completed,
    COUNTIF(a.status = 'no_show')           AS no_shows,
    SAFE_DIVIDE(
        COUNTIF(a.status = 'no_show'), COUNT(*)
    )                                       AS no_show_rate
FROM {{ ref('fct_appointments') }} AS a
WHERE a.appointment_date >= DATE_SUB(
    (SELECT MAX(appointment_date) FROM {{ ref('fct_appointments') }}),
    INTERVAL 12 MONTH
)
GROUP BY month, a.doctor_id
ORDER BY month DESC, total_appointments DESC;


-- 4. Inactive doctors (no completed appointment in last 90 days of dataset)
SELECT
    d.doctor_id,
    d.full_name,
    d.specialty_id,
    d.is_active,
    MAX(a.appointment_date)              AS last_appointment_date,
    DATE_DIFF(
        (SELECT MAX(appointment_date) FROM {{ ref('fct_appointments') }}),
        MAX(a.appointment_date),
        DAY
    )                                    AS days_inactive
FROM {{ ref('dim_doctors') }}        AS d
LEFT JOIN {{ ref('fct_appointments') }} AS a
    ON a.doctor_id = d.doctor_id AND a.status = 'completed'
GROUP BY d.doctor_id, d.full_name, d.specialty_id, d.is_active
HAVING days_inactive > 90 OR last_appointment_date IS NULL
ORDER BY days_inactive DESC NULLS FIRST;
