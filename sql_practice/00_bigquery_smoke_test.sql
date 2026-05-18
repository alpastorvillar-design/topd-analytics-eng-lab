-- 00_bigquery_smoke_test.sql: connectivity & schema validation
-- Run these in the BigQuery console after a fresh dbt run.
-- Each block should return data without errors.


-- 1. Row counts per mart table
select 'fct_appointments'       as table_name, COUNT(*) as row_count from `topd-lab.dbt_marts.fct_appointments`
union all
select 'fct_payments',                          COUNT(*) from `topd-lab.dbt_marts.fct_payments`
union all
select 'fct_leads',                             COUNT(*) from `topd-lab.dbt_marts.fct_leads`
union all
select 'dim_patients',                          COUNT(*) from `topd-lab.dbt_marts.dim_patients`
union all
select 'dim_doctors',                           COUNT(*) from `topd-lab.dbt_marts.dim_doctors`
union all
select 'dim_specialties',                       COUNT(*) from `topd-lab.dbt_marts.dim_specialties`
union all
select 'dim_countries',                         COUNT(*) from `topd-lab.dbt_marts.dim_countries`
union all
select 'agg_daily_business_kpis',               COUNT(*) from `topd-lab.dbt_marts.agg_daily_business_kpis`
union all
select 'mart_patient_retention',                COUNT(*) from `topd-lab.dbt_marts.mart_patient_retention`
order by table_name;


-- 2. Date range and status distribution in fct_appointments
select
    MIN(appointment_date)                   as earliest_date,
    MAX(appointment_date)                   as latest_date,
    COUNTIF(status = 'completed')           as completed,
    COUNTIF(status = 'cancelled')           as cancelled,
    COUNTIF(status = 'no_show')             as no_show,
    COUNTIF(status = 'scheduled')           as scheduled,
    COUNT(*)                                as total
from `topd-lab.dbt_marts.fct_appointments`;


-- 3. Revenue sanity check: total and average per appointment
select
    ROUND(SUM(amount_eur), 2)               as total_revenue_eur,
    ROUND(AVG(amount_eur), 2)               as avg_per_payment,
    COUNTIF(amount_eur <= 0)                as zero_or_negative,
    COUNTIF(amount_eur > 1000)              as above_1000_eur
from `topd-lab.dbt_marts.fct_payments`
where payment_status = 'paid';


-- 4. FK integrity: orphan appointments (should return 0 rows)
select COUNT(*) as orphan_appointments
from `topd-lab.dbt_marts.fct_appointments` as a
left join `topd-lab.dbt_marts.dim_patients` as p using (patient_id)
where p.patient_id is NULL;


-- 5. Partition metadata: confirm partitioning is active
select
    table_name,
    partition_id,
    total_rows,
    total_logical_bytes / POW(1024, 2)      as size_mb
from `topd-lab.dbt_marts.INFORMATION_SCHEMA.PARTITIONS`
where table_name = 'fct_appointments'
order by partition_id desc
limit 12;


-- 6. Latest daily KPI: quick sanity on the executive agg
select *
from `topd-lab.dbt_marts.agg_daily_business_kpis`
order by date desc
limit 7;
