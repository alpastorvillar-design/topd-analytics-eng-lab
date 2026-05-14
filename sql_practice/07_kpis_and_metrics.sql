-- =============================================================================
-- 07_kpis_and_metrics.sql  ·  Business KPIs & metric patterns
-- =============================================================================
-- Revenue metrics, period-over-period growth, LTV, retention rates,
-- funnel conversion, supply/demand ratios. All against the mart layer.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Core revenue KPIs with MoM, YoY and running total
-- ─────────────────────────────────────────────────────────────────────────────
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC(payment_date, MONTH)                 AS month,
        SUM(amount_eur)                                 AS revenue_eur
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY month
)
SELECT
    month,
    revenue_eur,
    LAG(revenue_eur, 1) OVER (ORDER BY month)           AS prev_month_revenue,
    LAG(revenue_eur, 12) OVER (ORDER BY month)          AS same_month_last_year,
    SAFE_DIVIDE(
        revenue_eur - LAG(revenue_eur, 1) OVER (ORDER BY month),
        LAG(revenue_eur, 1) OVER (ORDER BY month)
    )                                                   AS mom_growth,
    SAFE_DIVIDE(
        revenue_eur - LAG(revenue_eur, 12) OVER (ORDER BY month),
        LAG(revenue_eur, 12) OVER (ORDER BY month)
    )                                                   AS yoy_growth,
    SUM(revenue_eur) OVER (
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                   AS cumulative_revenue
FROM monthly_revenue
ORDER BY month;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Revenue MTD, QTD, YTD using date anchors
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    ROUND(SUM(CASE WHEN payment_date >= DATE_TRUNC(CURRENT_DATE(), MONTH)
                   THEN amount_eur ELSE 0 END), 2)      AS revenue_mtd,
    ROUND(SUM(CASE WHEN payment_date >= DATE_TRUNC(CURRENT_DATE(), QUARTER)
                   THEN amount_eur ELSE 0 END), 2)      AS revenue_qtd,
    ROUND(SUM(CASE WHEN payment_date >= DATE_TRUNC(CURRENT_DATE(), YEAR)
                   THEN amount_eur ELSE 0 END), 2)      AS revenue_ytd,
    ROUND(SUM(amount_eur), 2)                           AS revenue_all_time
FROM `topd-lab.dbt_marts.fct_payments`
WHERE payment_status = 'paid';


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Completion rate, no-show rate, cancellation rate by channel and month
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    DATE_TRUNC(appointment_date, MONTH)                 AS month,
    channel,
    COUNT(*)                                            AS total_appointments,
    COUNTIF(status = 'completed')                       AS completed,
    COUNTIF(status = 'no_show')                         AS no_show,
    COUNTIF(status = 'cancelled')                       AS cancelled,
    ROUND(SAFE_DIVIDE(COUNTIF(status = 'completed'), COUNT(*)), 4)  AS completion_rate,
    ROUND(SAFE_DIVIDE(COUNTIF(status = 'no_show'),   COUNT(*)), 4)  AS no_show_rate,
    ROUND(SAFE_DIVIDE(COUNTIF(status = 'cancelled'), COUNT(*)), 4)  AS cancellation_rate
FROM `topd-lab.dbt_marts.fct_appointments`
GROUP BY month, channel
ORDER BY month DESC, total_appointments DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Patient LTV: revenue + appointment frequency + active lifespan
-- ─────────────────────────────────────────────────────────────────────────────
WITH patient_revenue AS (
    SELECT
        a.patient_id,
        SUM(p.amount_eur)                               AS total_revenue_eur,
        COUNT(DISTINCT a.appointment_id)                AS total_appointments,
        MIN(a.appointment_date)                         AS first_appointment,
        MAX(a.appointment_date)                         AS last_appointment,
        DATE_DIFF(MAX(a.appointment_date), MIN(a.appointment_date), MONTH) AS lifespan_months
    FROM `topd-lab.dbt_marts.fct_appointments` AS a
    LEFT JOIN `topd-lab.dbt_marts.fct_payments` AS p
        ON a.appointment_id = p.appointment_id AND p.payment_status = 'paid'
    WHERE a.status = 'completed'
    GROUP BY a.patient_id
)
SELECT
    patient_id,
    ROUND(total_revenue_eur, 2)                         AS ltv_eur,
    total_appointments,
    lifespan_months,
    ROUND(SAFE_DIVIDE(total_revenue_eur, total_appointments), 2) AS avg_revenue_per_visit,
    ROUND(SAFE_DIVIDE(total_appointments, NULLIF(lifespan_months, 0)), 2) AS visits_per_month,
    NTILE(5) OVER (ORDER BY total_revenue_eur DESC)     AS ltv_quintile
FROM patient_revenue
ORDER BY ltv_eur DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Lead-to-revenue funnel with conversion rates per stage
-- ─────────────────────────────────────────────────────────────────────────────
WITH leads AS (
    SELECT DATE_TRUNC(created_at, MONTH) AS month, COUNT(*) AS total_leads
    FROM `topd-lab.dbt_marts.fct_leads`
    GROUP BY month
),
converted AS (
    SELECT DATE_TRUNC(created_at, MONTH) AS month, COUNT(*) AS converted_leads
    FROM `topd-lab.dbt_marts.fct_leads`
    WHERE lead_status = 'converted'
    GROUP BY month
),
paid AS (
    SELECT DATE_TRUNC(payment_date, MONTH) AS month, COUNT(*) AS paid_appointments
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
    GROUP BY month
)
SELECT
    l.month,
    l.total_leads,
    COALESCE(c.converted_leads, 0)                      AS converted_leads,
    COALESCE(p.paid_appointments, 0)                    AS paid_appointments,
    ROUND(SAFE_DIVIDE(c.converted_leads, l.total_leads), 4)             AS lead_conversion_rate,
    ROUND(SAFE_DIVIDE(p.paid_appointments, c.converted_leads), 4)       AS appt_to_payment_rate,
    ROUND(SAFE_DIVIDE(p.paid_appointments, l.total_leads), 4)           AS end_to_end_rate
FROM leads AS l
LEFT JOIN converted AS c USING (month)
LEFT JOIN paid      AS p USING (month)
ORDER BY l.month;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Doctor utilisation: booked slots vs available capacity
--    (proxy: completed / (completed + no_show + cancelled) per month)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    DATE_TRUNC(appointment_date, MONTH)                 AS month,
    d.specialty_id,
    COUNT(DISTINCT a.doctor_id)                         AS active_doctors,
    COUNT(*)                                            AS total_slots,
    COUNTIF(a.status = 'completed')                     AS completed_slots,
    ROUND(SAFE_DIVIDE(
        COUNTIF(a.status = 'completed'), COUNT(*)
    ), 4)                                               AS utilisation_rate,
    ROUND(SAFE_DIVIDE(
        COUNT(*), COUNT(DISTINCT a.doctor_id)
    ), 1)                                               AS avg_appointments_per_doctor
FROM `topd-lab.dbt_marts.fct_appointments` AS a
JOIN `topd-lab.dbt_marts.dim_doctors`      AS d USING (doctor_id)
GROUP BY month, d.specialty_id
ORDER BY month DESC, total_slots DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Cohort retention — month 0 through month 6 in one query
-- ─────────────────────────────────────────────────────────────────────────────
WITH first_appt AS (
    SELECT patient_id, DATE_TRUNC(MIN(appointment_date), MONTH) AS cohort_month
    FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE status = 'completed'
    GROUP BY patient_id
),
activity AS (
    SELECT patient_id, DATE_TRUNC(appointment_date, MONTH) AS activity_month
    FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE status = 'completed'
    GROUP BY patient_id, activity_month
),
cohort_activity AS (
    SELECT
        f.cohort_month,
        DATE_DIFF(a.activity_month, f.cohort_month, MONTH) AS offset_month,
        COUNT(DISTINCT f.patient_id)                        AS retained
    FROM first_appt AS f
    JOIN activity   AS a USING (patient_id)
    WHERE a.activity_month >= f.cohort_month
    GROUP BY f.cohort_month, offset_month
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM first_appt
    GROUP BY cohort_month
)
SELECT
    ca.cohort_month,
    cs.cohort_size,
    MAX(CASE WHEN offset_month = 0 THEN retained END)                   AS m0,
    ROUND(MAX(CASE WHEN offset_month = 1 THEN SAFE_DIVIDE(retained, cs.cohort_size) END), 4) AS ret_m1,
    ROUND(MAX(CASE WHEN offset_month = 2 THEN SAFE_DIVIDE(retained, cs.cohort_size) END), 4) AS ret_m2,
    ROUND(MAX(CASE WHEN offset_month = 3 THEN SAFE_DIVIDE(retained, cs.cohort_size) END), 4) AS ret_m3,
    ROUND(MAX(CASE WHEN offset_month = 4 THEN SAFE_DIVIDE(retained, cs.cohort_size) END), 4) AS ret_m4,
    ROUND(MAX(CASE WHEN offset_month = 5 THEN SAFE_DIVIDE(retained, cs.cohort_size) END), 4) AS ret_m5,
    ROUND(MAX(CASE WHEN offset_month = 6 THEN SAFE_DIVIDE(retained, cs.cohort_size) END), 4) AS ret_m6
FROM cohort_activity AS ca
JOIN cohort_sizes    AS cs USING (cohort_month)
GROUP BY ca.cohort_month, cs.cohort_size
ORDER BY ca.cohort_month;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Supply vs demand by specialty and country
-- ─────────────────────────────────────────────────────────────────────────────
WITH demand AS (
    SELECT
        DATE_TRUNC(appointment_date, MONTH)             AS month,
        specialty_id,
        country_id,
        COUNT(*)                                        AS appointments_requested,
        COUNT(DISTINCT patient_id)                      AS unique_patients
    FROM `topd-lab.dbt_marts.fct_appointments`
    GROUP BY month, specialty_id, country_id
),
supply AS (
    SELECT
        specialty_id,
        country_id,
        COUNT(DISTINCT doctor_id)                       AS active_doctors
    FROM `topd-lab.dbt_marts.dim_doctors`
    WHERE is_active = TRUE
    GROUP BY specialty_id, country_id
)
SELECT
    d.month,
    s.specialty_id,
    d.country_id,
    s.active_doctors,
    d.appointments_requested,
    d.unique_patients,
    ROUND(SAFE_DIVIDE(d.appointments_requested, s.active_doctors), 1) AS demand_per_doctor
FROM demand AS d
JOIN supply AS s USING (specialty_id, country_id)
ORDER BY d.month DESC, demand_per_doctor DESC;
