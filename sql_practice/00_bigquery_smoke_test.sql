-- =============================================================================
-- 00_bigquery_smoke_test.sql  ·  Connectivity & schema validation
-- =============================================================================
-- Run these queries in the BigQuery console to confirm the pipeline is healthy
-- after a fresh dbt run. Each block should return data without errors.
-- =============================================================================


-- 1. Row counts per mart table
SELECT 'fct_appointments'       AS table_name, COUNT(*) AS row_count FROM `topd-lab.dbt_marts.fct_appointments`
UNION ALL
SELECT 'fct_payments',                          COUNT(*) FROM `topd-lab.dbt_marts.fct_payments`
UNION ALL
SELECT 'fct_leads',                             COUNT(*) FROM `topd-lab.dbt_marts.fct_leads`
UNION ALL
SELECT 'dim_patients',                          COUNT(*) FROM `topd-lab.dbt_marts.dim_patients`
UNION ALL
SELECT 'dim_doctors',                           COUNT(*) FROM `topd-lab.dbt_marts.dim_doctors`
UNION ALL
SELECT 'dim_specialties',                       COUNT(*) FROM `topd-lab.dbt_marts.dim_specialties`
UNION ALL
SELECT 'dim_countries',                         COUNT(*) FROM `topd-lab.dbt_marts.dim_countries`
UNION ALL
SELECT 'agg_daily_business_kpis',               COUNT(*) FROM `topd-lab.dbt_marts.agg_daily_business_kpis`
UNION ALL
SELECT 'mart_patient_retention',                COUNT(*) FROM `topd-lab.dbt_marts.mart_patient_retention`
ORDER BY table_name;


-- 2. Date range and status distribution in fct_appointments
SELECT
    MIN(appointment_date)                   AS earliest_date,
    MAX(appointment_date)                   AS latest_date,
    COUNTIF(status = 'completed')           AS completed,
    COUNTIF(status = 'cancelled')           AS cancelled,
    COUNTIF(status = 'no_show')             AS no_show,
    COUNTIF(status = 'scheduled')           AS scheduled,
    COUNT(*)                                AS total
FROM `topd-lab.dbt_marts.fct_appointments`;


-- 3. Revenue sanity check — total and average per appointment
SELECT
    ROUND(SUM(amount_eur), 2)               AS total_revenue_eur,
    ROUND(AVG(amount_eur), 2)               AS avg_per_payment,
    COUNTIF(amount_eur <= 0)                AS zero_or_negative,
    COUNTIF(amount_eur > 1000)              AS above_1000_eur
FROM `topd-lab.dbt_marts.fct_payments`
WHERE payment_status = 'paid';


-- 4. FK integrity: orphan appointments (should return 0 rows)
SELECT COUNT(*) AS orphan_appointments
FROM `topd-lab.dbt_marts.fct_appointments` AS a
LEFT JOIN `topd-lab.dbt_marts.dim_patients` AS p USING (patient_id)
WHERE p.patient_id IS NULL;


-- 5. Partition metadata — confirm partitioning is active
SELECT
    table_name,
    partition_id,
    total_rows,
    total_logical_bytes / POW(1024, 2)      AS size_mb
FROM `topd-lab.dbt_marts.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'fct_appointments'
ORDER BY partition_id DESC
LIMIT 12;


-- 6. Latest daily KPI — quick sanity on the executive agg
SELECT *
FROM `topd-lab.dbt_marts.agg_daily_business_kpis`
ORDER BY date DESC
LIMIT 7;
