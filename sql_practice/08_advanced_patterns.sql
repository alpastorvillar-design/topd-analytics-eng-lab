-- =============================================================================
-- 08_advanced_patterns.sql  ·  PIVOT, ARRAY, JSON, approximate aggregations
-- =============================================================================
-- Patterns that come up in production analytics: manual pivot with conditional
-- aggregation, ARRAY_AGG for nesting, STRUCT, JSON extraction, APPROX functions,
-- EXCEPT/INTERSECT, and dynamic date spine generation.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Manual PIVOT: monthly revenue per channel as columns
--    BigQuery has no PIVOT keyword; use conditional aggregation.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    DATE_TRUNC(payment_date, MONTH)                         AS month,
    ROUND(SUM(CASE WHEN channel = 'web'    THEN amount_eur ELSE 0 END), 2) AS web_revenue,
    ROUND(SUM(CASE WHEN channel = 'app'    THEN amount_eur ELSE 0 END), 2) AS app_revenue,
    ROUND(SUM(CASE WHEN channel = 'phone'  THEN amount_eur ELSE 0 END), 2) AS phone_revenue,
    ROUND(SUM(CASE WHEN channel = 'referral' THEN amount_eur ELSE 0 END), 2) AS referral_revenue,
    ROUND(SUM(amount_eur), 2)                               AS total_revenue
FROM `topd-lab.dbt_marts.fct_payments` AS p
JOIN `topd-lab.dbt_marts.fct_appointments` AS a USING (appointment_id)
WHERE p.payment_status = 'paid'
GROUP BY month
ORDER BY month;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. UNPIVOT: convert wide retention columns to long format for charting
--    (mart_patient_retention has ret_m1 through ret_m6 as separate columns)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT cohort_month, cohort_size, month_offset, retention_rate
FROM `topd-lab.dbt_marts.mart_patient_retention`
UNPIVOT (
    retention_rate FOR month_offset IN (
        retention_rate_m1 AS 'M+1',
        retention_rate_m2 AS 'M+2',
        retention_rate_m3 AS 'M+3',
        retention_rate_m4 AS 'M+4',
        retention_rate_m5 AS 'M+5',
        retention_rate_m6 AS 'M+6'
    )
)
ORDER BY cohort_month, month_offset;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. ARRAY_AGG: aggregate child rows as an array inside the parent row
--    One row per patient with all their appointment IDs as an array.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    patient_id,
    COUNT(*)                                            AS total_appointments,
    ARRAY_AGG(
        STRUCT(appointment_id, appointment_date, status, amount_eur)
        ORDER BY appointment_date
    )                                                   AS appointments
FROM `topd-lab.dbt_marts.fct_appointments` AS a
LEFT JOIN `topd-lab.dbt_marts.fct_payments` AS p USING (appointment_id)
WHERE a.status = 'completed'
GROUP BY patient_id
LIMIT 10;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. UNNEST arrays: one row per specialty per doctor
--    Hypothetical: if doctors.specialties were ARRAY<STRING>
-- ─────────────────────────────────────────────────────────────────────────────
-- Real use case: explode an array column from a JSON source or nested BQ table.
SELECT
    d.doctor_id,
    d.full_name,
    specialty_tag
FROM `topd-lab.dbt_marts.dim_doctors` AS d
CROSS JOIN UNNEST(['cardiology', 'general', 'pediatrics']) AS specialty_tag
-- In practice: CROSS JOIN UNNEST(d.specialty_tags) AS specialty_tag
LIMIT 20;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. APPROX functions: faster aggregations on large tables
--    APPROX_COUNT_DISTINCT uses HyperLogLog — ~2% error, 10-100x faster.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    DATE_TRUNC(appointment_date, MONTH)                 AS month,
    COUNT(DISTINCT patient_id)                          AS exact_unique_patients,
    APPROX_COUNT_DISTINCT(patient_id)                   AS approx_unique_patients,
    APPROX_QUANTILES(amount_eur, 4)                     AS revenue_quartiles  -- [p0, p25, p50, p75, p100]
FROM `topd-lab.dbt_marts.fct_appointments` AS a
LEFT JOIN `topd-lab.dbt_marts.fct_payments` AS p USING (appointment_id)
GROUP BY month
ORDER BY month;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. EXCEPT / INTERSECT: set operations for patient overlap analysis
-- ─────────────────────────────────────────────────────────────────────────────
-- Patients who booked online but never via phone:
SELECT patient_id FROM `topd-lab.dbt_marts.fct_appointments` WHERE channel = 'web'
EXCEPT DISTINCT
SELECT patient_id FROM `topd-lab.dbt_marts.fct_appointments` WHERE channel = 'phone';

-- Patients who used both web and phone:
SELECT patient_id FROM `topd-lab.dbt_marts.fct_appointments` WHERE channel = 'web'
INTERSECT DISTINCT
SELECT patient_id FROM `topd-lab.dbt_marts.fct_appointments` WHERE channel = 'phone';


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Date spine with LEFT JOIN: zero-fill missing days in a time series
-- ─────────────────────────────────────────────────────────────────────────────
WITH spine AS (
    SELECT d AS date
    FROM UNNEST(
        GENERATE_DATE_ARRAY('2024-01-01', '2024-12-31', INTERVAL 1 DAY)
    ) AS d
),
daily_revenue AS (
    SELECT
        payment_date,
        SUM(amount_eur)                                 AS revenue_eur,
        COUNT(*)                                        AS payments
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
      AND payment_date BETWEEN '2024-01-01' AND '2024-12-31'
    GROUP BY payment_date
)
SELECT
    s.date,
    COALESCE(r.revenue_eur, 0)                          AS revenue_eur,
    COALESCE(r.payments, 0)                             AS payments,
    -- 7-day rolling average
    AVG(COALESCE(r.revenue_eur, 0)) OVER (
        ORDER BY s.date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )                                                   AS revenue_7d_avg
FROM spine AS s
LEFT JOIN daily_revenue AS r ON s.date = r.payment_date
ORDER BY s.date;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Recursive CTE: patient referral chain (depth-limited)
--    Useful when source data has a self-referencing FK (referrer_patient_id).
-- ─────────────────────────────────────────────────────────────────────────────
-- Note: BigQuery supports recursive CTEs since 2022 (GA).
-- Hypothetical column: patients.referrer_patient_id
WITH RECURSIVE referral_chain AS (
    -- Anchor: patients with no referrer (root nodes)
    SELECT
        patient_id,
        CAST(NULL AS STRING)    AS referrer_patient_id,
        0                       AS depth,
        CAST(patient_id AS STRING) AS path
    FROM `topd-lab.dbt_marts.dim_patients`
    WHERE referrer_patient_id IS NULL  -- hypothetical column

    UNION ALL

    -- Recursive: join referred patients to their referrers
    SELECT
        p.patient_id,
        p.referrer_patient_id,
        rc.depth + 1,
        CONCAT(rc.path, ' -> ', p.patient_id)
    FROM `topd-lab.dbt_marts.dim_patients` AS p
    JOIN referral_chain AS rc
        ON p.referrer_patient_id = rc.patient_id
    WHERE rc.depth < 5  -- prevent infinite loops
)
SELECT patient_id, depth, path
FROM referral_chain
ORDER BY depth, patient_id;


-- ─────────────────────────────────────────────────────────────────────────────
-- 9. STRING_AGG: concatenate values within a group
-- ─────────────────────────────────────────────────────────────────────────────
-- Specialties visited by each patient as a comma-separated string:
SELECT
    patient_id,
    COUNT(DISTINCT specialty_id)                        AS distinct_specialties,
    STRING_AGG(DISTINCT s.specialty_name ORDER BY s.specialty_name) AS specialties_visited
FROM `topd-lab.dbt_marts.fct_appointments` AS a
JOIN `topd-lab.dbt_marts.dim_specialties`  AS s USING (specialty_id)
WHERE a.status = 'completed'
GROUP BY patient_id
HAVING COUNT(DISTINCT specialty_id) > 1
ORDER BY distinct_specialties DESC
LIMIT 20;


-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Percentile / median revenue per specialty using APPROX_QUANTILES
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    s.specialty_name,
    COUNT(*)                                                AS total_payments,
    ROUND(AVG(p.amount_eur), 2)                             AS avg_revenue,
    APPROX_QUANTILES(p.amount_eur, 100)[OFFSET(50)]         AS median_revenue,
    APPROX_QUANTILES(p.amount_eur, 100)[OFFSET(25)]         AS p25_revenue,
    APPROX_QUANTILES(p.amount_eur, 100)[OFFSET(75)]         AS p75_revenue,
    APPROX_QUANTILES(p.amount_eur, 100)[OFFSET(95)]         AS p95_revenue
FROM `topd-lab.dbt_marts.fct_payments`    AS p
JOIN `topd-lab.dbt_marts.fct_appointments` AS a USING (appointment_id)
JOIN `topd-lab.dbt_marts.dim_specialties`  AS s USING (specialty_id)
WHERE p.payment_status = 'paid'
GROUP BY s.specialty_name
ORDER BY median_revenue DESC;
