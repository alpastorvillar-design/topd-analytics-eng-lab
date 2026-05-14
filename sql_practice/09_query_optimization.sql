-- =============================================================================
-- 09_query_optimization.sql  ·  Performance & cost patterns in BigQuery
-- =============================================================================
-- Partition pruning, clustering, avoiding full scans, materialisation strategy,
-- slot usage, approximate vs exact aggregations, and query anti-patterns.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Partition pruning: always filter on the partition column
--    fct_appointments is partitioned by appointment_date (MONTH granularity).
--    Without the filter, BQ scans the entire table.
-- ─────────────────────────────────────────────────────────────────────────────

-- BAD: full table scan, processes all partitions
SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed';

-- GOOD: partition filter added — only the relevant months are scanned
SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date >= '2024-01-01'
  AND status = 'completed';

-- GOOD: dynamic — always last 90 days, no hardcoded dates
SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  AND status = 'completed';


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Clustering benefit: filter on cluster columns after partition pruning
--    fct_appointments clusters on [country_id, specialty_id, status].
--    BQ skips blocks that don't match — no cost reduction, but faster execution.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    specialty_id,
    COUNT(*)                AS appointments,
    SUM(amount_eur)         AS revenue
FROM `topd-lab.dbt_marts.fct_appointments` AS a
LEFT JOIN `topd-lab.dbt_marts.fct_payments` AS p USING (appointment_id)
WHERE appointment_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 365 DAY)  -- partition
  AND country_id   = 'ES'                                              -- cluster col 1
  AND status       = 'completed'                                       -- cluster col 3
GROUP BY specialty_id;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. SELECT only the columns you need — avoid SELECT *
--    BigQuery bills by bytes scanned. Selecting 3 columns from a 50-column
--    table can reduce cost by 94%.
-- ─────────────────────────────────────────────────────────────────────────────

-- BAD: reads all columns including large ones like cancellation_reason, source_lead_id
SELECT *
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date >= '2024-01-01';

-- GOOD: only the 4 columns you actually use
SELECT appointment_id, patient_id, status, appointment_date
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date >= '2024-01-01';


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Filter before joining — push predicates into CTEs
-- ─────────────────────────────────────────────────────────────────────────────

-- BAD: joins full tables, then filters
SELECT a.appointment_id, p.amount_eur
FROM `topd-lab.dbt_marts.fct_appointments` AS a
JOIN `topd-lab.dbt_marts.fct_payments`     AS p USING (appointment_id)
WHERE a.appointment_date >= '2024-01-01'
  AND p.payment_status = 'paid';

-- GOOD: filter each table first, then join the smaller result sets
WITH recent_appointments AS (
    SELECT appointment_id, patient_id, doctor_id, appointment_date
    FROM `topd-lab.dbt_marts.fct_appointments`
    WHERE appointment_date >= '2024-01-01'
),
paid_payments AS (
    SELECT appointment_id, amount_eur
    FROM `topd-lab.dbt_marts.fct_payments`
    WHERE payment_status = 'paid'
)
SELECT a.appointment_id, a.patient_id, p.amount_eur
FROM recent_appointments AS a
JOIN paid_payments        AS p USING (appointment_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Avoid DISTINCT when GROUP BY is sufficient
-- ─────────────────────────────────────────────────────────────────────────────

-- BAD: DISTINCT over a large result set forces a full sort
SELECT DISTINCT patient_id, DATE_TRUNC(appointment_date, MONTH) AS month
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed';

-- GOOD: GROUP BY is equivalent and the planner optimises it better
SELECT patient_id, DATE_TRUNC(appointment_date, MONTH) AS month
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed'
GROUP BY patient_id, month;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Use APPROX_COUNT_DISTINCT for cardinality estimates on large tables
--    ~2% error, significantly faster and cheaper than COUNT(DISTINCT ...).
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    DATE_TRUNC(appointment_date, MONTH)     AS month,
    -- Exact: expensive on 50M+ rows
    COUNT(DISTINCT patient_id)              AS exact_unique_patients,
    -- Approximate: use for dashboards where 2% error is acceptable
    APPROX_COUNT_DISTINCT(patient_id)       AS approx_unique_patients
FROM `topd-lab.dbt_marts.fct_appointments`
GROUP BY month
ORDER BY month;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Avoid correlated subqueries — rewrite as JOIN or window function
-- ─────────────────────────────────────────────────────────────────────────────

-- BAD: correlated subquery runs once per row (O(n²) in the worst case)
SELECT
    doctor_id,
    (SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments` a2
     WHERE a2.doctor_id = a1.doctor_id AND a2.status = 'completed') AS completed
FROM `topd-lab.dbt_marts.fct_appointments` AS a1
GROUP BY doctor_id;

-- GOOD: pre-aggregate, then join
WITH doctor_completed AS (
    SELECT doctor_id, COUNTIF(status = 'completed') AS completed
    FROM `topd-lab.dbt_marts.fct_appointments`
    GROUP BY doctor_id
)
SELECT * FROM doctor_completed ORDER BY completed DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Materialisation strategy: when to use TABLE vs VIEW in dbt
-- ─────────────────────────────────────────────────────────────────────────────
-- These are not executable queries — they illustrate the decision logic.

-- VIEW (staging, intermediate):
--   + No storage cost
--   + Always reflects latest data
--   - Query runs the full transformation every time
--   - Expensive if referenced by multiple downstream models

-- TABLE (marts):
--   + Computed once, read many times
--   + Partition pruning applies at query time
--   - Storage cost (cheap in BQ for typical mart sizes)
--   - Needs scheduled refresh to stay current

-- INCREMENTAL (high-volume facts):
--   + Only processes new/changed rows per run
--   + Dramatically reduces dbt run time and BQ compute cost
--   - Requires a reliable updated_at column
--   - More complex to backfill

-- fct_appointments with incremental materialisation would look like:
-- {{ config(materialized='incremental', unique_key='appointment_id',
--           incremental_strategy='merge') }}
-- ... WHERE updated_at > (SELECT MAX(updated_at) FROM {{ this }})


-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Bytes processed estimation — check before running expensive queries
-- ─────────────────────────────────────────────────────────────────────────────
-- In BigQuery console: paste query, click the green checkmark (not Run).
-- The validator shows estimated bytes processed in the top right.
-- BQ charges $5 per TB scanned (on-demand pricing).
-- A query scanning 10 GB costs ~$0.05. Scanning 10 TB costs ~$50.

-- To check table size:
SELECT
    table_name,
    ROUND(size_bytes / POW(1024, 3), 3)     AS size_gb,
    row_count
FROM `topd-lab.dbt_marts.__TABLES__`
ORDER BY size_bytes DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Window function vs subquery: performance comparison
--     Window functions run in a single pass; subqueries may rescan the table.
-- ─────────────────────────────────────────────────────────────────────────────

-- BAD: subquery rescans fct_appointments to get the max date per patient
SELECT
    a.patient_id,
    a.appointment_id,
    a.appointment_date
FROM `topd-lab.dbt_marts.fct_appointments` AS a
WHERE a.appointment_date = (
    SELECT MAX(appointment_date)
    FROM `topd-lab.dbt_marts.fct_appointments` AS a2
    WHERE a2.patient_id = a.patient_id
)
  AND a.status = 'completed';

-- GOOD: window function — single scan, QUALIFY eliminates the subquery
SELECT patient_id, appointment_id, appointment_date
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed'
QUALIFY ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY appointment_date DESC) = 1;
