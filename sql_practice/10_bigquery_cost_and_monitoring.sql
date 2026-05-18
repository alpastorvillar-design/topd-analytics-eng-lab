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
SELECT
    creation_time,
    user_email,
    ROUND(total_bytes_processed / POW(10, 12), 4)   AS tb_processed,
    ROUND(total_bytes_processed / POW(10, 12) * 6.25, 4) AS estimated_usd,
    ROUND(total_slot_ms / 1000, 1)                  AS slot_seconds,
    job_id,
    SUBSTR(query, 1, 120)                            AS query_preview
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE
    creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
    AND error_result IS NULL
ORDER BY total_bytes_processed DESC
LIMIT 20;


-- ── 2. Daily spend summary ───────────────────────────────────
SELECT
    DATE(creation_time)                              AS query_date,
    COUNT(*)                                         AS query_count,
    ROUND(SUM(total_bytes_processed) / POW(10, 12), 4) AS total_tb,
    ROUND(SUM(total_bytes_processed) / POW(10, 12) * 6.25, 4) AS estimated_usd
FROM `region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE
    creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND job_type = 'QUERY'
    AND state = 'DONE'
GROUP BY query_date
ORDER BY query_date DESC;


-- ── 3. Partition pruning effectiveness ──────────────────────
-- Compare bytes processed on fct_appointments:
-- Query A uses partition filter (cheap)
-- Query B scans the full table (expensive)

-- A: Partition-pruned (scans 1 month only)
SELECT COUNT(*)
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date BETWEEN '2024-01-01' AND '2024-01-31';

-- B: Full table scan (no partition filter — avoid in production)
SELECT COUNT(*)
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed';

-- Compare "Bytes processed" in the query results panel.
-- A should process ~1/36 of what B processes.


-- ── 4. Table storage and row counts ─────────────────────────
SELECT
    table_id,
    ROUND(size_bytes / POW(10, 6), 2)               AS size_mb,
    row_count,
    DATE(TIMESTAMP_MILLIS(last_modified_time))       AS last_modified
FROM `topd-lab.dbt_marts.__TABLES__`
ORDER BY size_bytes DESC;


-- ── 5. Partition metadata for fct_appointments ──────────────
-- Verifies partitioning is working: each row is one month partition.
SELECT
    table_name,
    partition_id,
    total_rows,
    total_logical_bytes,
    last_modified_time
FROM `topd-lab.dbt_marts.INFORMATION_SCHEMA.PARTITIONS`
WHERE table_name = 'fct_appointments'
ORDER BY partition_id;


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
