-- ============================================================
-- 10 · BigQuery Cost & Monitoring
-- ============================================================
-- INFORMATION_SCHEMA queries to track bytes processed, estimated
-- cost, and identify the most expensive queries in the project.
-- Run these in the BigQuery console against topd-lab.
-- ============================================================


-- ── 1. Top 20 most expensive queries (last 7 days) ──────────
-- Shows who ran what, how many bytes processed, and estimated
-- cost at $6.25 per TB (on-demand pricing).
select
    creation_time,
    user_email,
    ROUND(total_bytes_processed / POW(10, 12), 4)   as tb_processed,
    ROUND(total_bytes_processed / POW(10, 12) * 6.25, 4) as estimated_usd,
    ROUND(total_slot_ms / 1000, 1)                  as slot_seconds,
    job_id,
    SUBSTR(query, 1, 120)                            as query_preview
from `region-eu`.information_schema.jobs_by_project
where
    creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), interval 7 day)
    and job_type = 'QUERY'
    and state = 'DONE'
    and error_result is NULL
order by total_bytes_processed desc
limit 20;


-- ── 2. Daily spend summary ───────────────────────────────────
select
    DATE(creation_time)                              as query_date,
    COUNT(*)                                         as query_count,
    ROUND(SUM(total_bytes_processed) / POW(10, 12), 4) as total_tb,
    ROUND(SUM(total_bytes_processed) / POW(10, 12) * 6.25, 4) as estimated_usd
from `region-eu`.information_schema.jobs_by_project
where
    creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), interval 30 day)
    and job_type = 'QUERY'
    and state = 'DONE'
group by query_date
order by query_date desc;


-- ── 3. Partition pruning effectiveness ──────────────────────
-- Compare bytes processed on fct_appointments:
-- Query A uses partition filter (cheap)
-- Query B scans the full table (expensive)

-- A: Partition-pruned (scans 1 month only)
select COUNT(*)
from `topd-lab.dbt_marts.fct_appointments`
where appointment_date between '2024-01-01' and '2024-01-31';

-- B: Full table scan (no partition filter — avoid in production)
select COUNT(*)
from `topd-lab.dbt_marts.fct_appointments`
where status = 'completed';

-- Compare "Bytes processed" in the query results panel.
-- A should process ~1/36 of what B processes.


-- ── 4. Table storage and row counts ─────────────────────────
select
    table_id,
    ROUND(size_bytes / POW(10, 6), 2)               as size_mb,
    row_count,
    DATE(TIMESTAMP_MILLIS(last_modified_time))       as last_modified
from `topd-lab.dbt_marts.__TABLES__`
order by size_bytes desc;


-- ── 5. Partition metadata for fct_appointments ──────────────
-- Verifies partitioning is working: each row is one month partition.
select
    table_name,
    partition_id,
    total_rows,
    total_logical_bytes,
    last_modified_time
from `topd-lab.dbt_marts.INFORMATION_SCHEMA.PARTITIONS`
where table_name = 'fct_appointments'
order by partition_id;


-- ── 6. Dry-run cost estimate (bq CLI) ───────────────────────
-- Run from terminal to estimate bytes WITHOUT executing the query.
-- Replace the SQL with any query you want to cost-check.
--
-- bq query \
--   --use_legacy_sql=false \
--   --dry_run \
--   'SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments`
--    WHERE appointment_date >= "2024-01-01"'
--
-- Output: "Query successfully validated. Bytes processed: X"
