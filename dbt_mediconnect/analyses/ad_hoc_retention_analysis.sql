-- ad_hoc_retention_analysis.sql
-- Exploratory analysis of patient retention patterns.
-- Run directly in dbt Cloud IDE or BigQuery Console.
-- Not part of the production DAG.

-- 1. Monthly active patients over time
SELECT
    DATE_TRUNC(appointment_date, MONTH)     AS month,
    COUNT(DISTINCT patient_id)              AS active_patients
FROM {{ ref('fct_appointments') }}
WHERE status = 'completed'
GROUP BY month
ORDER BY month;


-- 2. Retention pivot: cohort rows × months_since_acquisition columns (M0–M5)
WITH cohort_data AS (
    SELECT
        cohort_month,
        cohort_size,
        months_since_acquisition,
        retention_rate
    FROM {{ ref('mart_patient_retention') }}
    WHERE months_since_acquisition <= 5
)
SELECT
    FORMAT_DATE('%Y-%m', cohort_month)                      AS cohort,
    cohort_size,
    MAX(IF(months_since_acquisition = 0, ROUND(retention_rate * 100, 1), NULL)) AS m0_pct,
    MAX(IF(months_since_acquisition = 1, ROUND(retention_rate * 100, 1), NULL)) AS m1_pct,
    MAX(IF(months_since_acquisition = 2, ROUND(retention_rate * 100, 1), NULL)) AS m2_pct,
    MAX(IF(months_since_acquisition = 3, ROUND(retention_rate * 100, 1), NULL)) AS m3_pct,
    MAX(IF(months_since_acquisition = 4, ROUND(retention_rate * 100, 1), NULL)) AS m4_pct,
    MAX(IF(months_since_acquisition = 5, ROUND(retention_rate * 100, 1), NULL)) AS m5_pct
FROM cohort_data
GROUP BY cohort, cohort_size
ORDER BY cohort;


-- 3. Patient segment distribution (active / at_risk / churned)
SELECT
    patient_segment,
    COUNT(*)                            AS patients,
    SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()) AS pct_of_total
FROM (
    SELECT DISTINCT
        patient_id,
        CASE
            WHEN DATE_DIFF(CURRENT_DATE(),
                 MAX(appointment_date) OVER (PARTITION BY patient_id), DAY) <= 90
                 THEN 'active'
            WHEN DATE_DIFF(CURRENT_DATE(),
                 MAX(appointment_date) OVER (PARTITION BY patient_id), DAY) <= 365
                 THEN 'at_risk'
            ELSE 'churned'
        END AS patient_segment
    FROM {{ ref('fct_appointments') }}
    WHERE status = 'completed'
)
GROUP BY patient_segment
ORDER BY patients DESC;


-- 4. Patients with second appointment within 90 days (by acquisition month)
WITH first_appts AS (
    SELECT patient_id, MIN(appointment_date) AS first_date
    FROM {{ ref('fct_appointments') }}
    WHERE status = 'completed'
    GROUP BY patient_id
),
second_appts AS (
    SELECT
        f.patient_id,
        f.first_date,
        MIN(a.appointment_date) AS second_date
    FROM first_appts AS f
    LEFT JOIN {{ ref('fct_appointments') }} AS a
        ON  a.patient_id     = f.patient_id
        AND a.appointment_date > f.first_date
        AND a.status         = 'completed'
    GROUP BY f.patient_id, f.first_date
)
SELECT
    DATE_TRUNC(first_date, MONTH)                       AS acquisition_month,
    COUNT(*)                                            AS new_patients,
    COUNTIF(DATE_DIFF(second_date, first_date, DAY) <= 90) AS returned_90d,
    SAFE_DIVIDE(
        COUNTIF(DATE_DIFF(second_date, first_date, DAY) <= 90),
        COUNT(*)
    )                                                   AS return_rate_90d
FROM second_appts
GROUP BY acquisition_month
ORDER BY acquisition_month;
