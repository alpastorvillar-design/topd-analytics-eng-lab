-- 09_query_optimization.sql: performance y coste en BigQuery
-- Partition pruning, clustering, evitar full scans, estrategia de
-- materialización, uso de slots, approximate vs exact y anti-patrones.


-- 1. Partition pruning: filtrar siempre por la columna de partición.
--    fct_appointments está particionada por appointment_date (MONTH).
--    Sin filtro, BQ escanea toda la tabla.

-- MAL: full table scan, procesa todas las particiones
SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed';

-- BIEN: filtro de partición añadido, solo se escanean los meses relevantes
SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date >= '2024-01-01'
  AND status = 'completed';

-- BIEN: dinámico, últimos 90 días anclados al máximo del dataset.
-- Se usa MAX(appointment_date) en vez de CURRENT_DATE() porque el dataset
-- sintético cubre 2022-2024 y CURRENT_DATE() puede dejar la ventana vacía.
SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date >= DATE_SUB(
    (SELECT MAX(appointment_date) FROM `topd-lab.dbt_marts.fct_appointments`),
    INTERVAL 90 DAY
)
  AND status = 'completed';


-- 2. Clustering: filtrar por columnas de cluster tras partition pruning.
--    fct_appointments clusters por [country_id, specialty_id, status].
--    BQ salta bloques que no coinciden. Sin reducir coste, acelera la ejecución.
--    Las columnas se prefijan con el alias porque specialty_id, country_id
--    y amount_eur existen en ambas tablas tras USING(appointment_id).
SELECT
    a.specialty_id,
    COUNT(*)                AS appointments,
    SUM(p.amount_eur)       AS revenue
FROM `topd-lab.dbt_marts.fct_appointments` AS a
LEFT JOIN `topd-lab.dbt_marts.fct_payments` AS p USING (appointment_id)
WHERE a.appointment_date >= DATE_SUB(
    (SELECT MAX(appointment_date) FROM `topd-lab.dbt_marts.fct_appointments`),
    INTERVAL 365 DAY
)
  AND a.country_id = 'ES'
  AND a.status     = 'completed'
GROUP BY a.specialty_id;


-- 3. SELECT solo las columnas necesarias, evitar SELECT *.
--    BigQuery factura por bytes escaneados. Seleccionar 3 columnas de una
--    tabla de 50 puede reducir el coste un 94%.

-- MAL: lee todas las columnas, incluidas las grandes
SELECT *
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date >= '2024-01-01';

-- BIEN: solo las 4 columnas que se usan
SELECT appointment_id, patient_id, status, appointment_date
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE appointment_date >= '2024-01-01';


-- 4. Filtrar antes de unir: empujar predicados dentro de CTEs.

-- MAL: une tablas completas y luego filtra
SELECT a.appointment_id, p.amount_eur
FROM `topd-lab.dbt_marts.fct_appointments` AS a
JOIN `topd-lab.dbt_marts.fct_payments`     AS p USING (appointment_id)
WHERE a.appointment_date >= '2024-01-01'
  AND p.payment_status = 'paid';

-- BIEN: filtrar cada tabla antes del join
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


-- 5. Evitar DISTINCT cuando GROUP BY basta.

-- MAL: DISTINCT sobre un set grande fuerza un sort completo
SELECT DISTINCT patient_id, DATE_TRUNC(appointment_date, MONTH) AS month
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed';

-- BIEN: GROUP BY es equivalente y el planner lo optimiza mejor
SELECT patient_id, DATE_TRUNC(appointment_date, MONTH) AS month
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed'
GROUP BY patient_id, month;


-- 6. Usar APPROX_COUNT_DISTINCT para cardinality en tablas grandes.
--    ~2% error, mucho más rápido y barato que COUNT(DISTINCT ...).
SELECT
    DATE_TRUNC(appointment_date, MONTH)     AS month,
    -- Exact: caro en tablas de 50M+ filas
    COUNT(DISTINCT patient_id)              AS exact_unique_patients,
    -- Approximate: válido en dashboards donde 2% de error es aceptable
    APPROX_COUNT_DISTINCT(patient_id)       AS approx_unique_patients
FROM `topd-lab.dbt_marts.fct_appointments`
GROUP BY month
ORDER BY month;


-- 7. Evitar subqueries correlacionadas: reescribir como JOIN o window function.

-- MAL: subquery correlacionada se ejecuta una vez por fila
SELECT
    doctor_id,
    (SELECT COUNT(*) FROM `topd-lab.dbt_marts.fct_appointments` a2
     WHERE a2.doctor_id = a1.doctor_id AND a2.status = 'completed') AS completed
FROM `topd-lab.dbt_marts.fct_appointments` AS a1
GROUP BY doctor_id;

-- BIEN: pre-agregar y luego unir
WITH doctor_completed AS (
    SELECT doctor_id, COUNTIF(status = 'completed') AS completed
    FROM `topd-lab.dbt_marts.fct_appointments`
    GROUP BY doctor_id
)
SELECT * FROM doctor_completed ORDER BY completed DESC;


-- 8. Estrategia de materialización: TABLE vs VIEW vs INCREMENTAL en dbt.
--    Estos comentarios ilustran la decisión, no son ejecutables.

-- VIEW (staging, intermediate):
--   + Sin coste de storage
--   + Refleja siempre los datos más recientes
--   - Ejecuta la transformación entera en cada query
--   - Costoso si lo referencian varios modelos downstream

-- TABLE (marts):
--   + Calculada una vez, leída muchas
--   + Partition pruning aplica al consultar
--   - Coste de storage (barato en BQ para marts típicos)
--   - Requiere refresh programado para mantenerse actualizada

-- INCREMENTAL (facts de alto volumen):
--   + Solo procesa filas nuevas / cambiadas por run
--   + Reduce tiempo de dbt run y compute de BQ
--   - Requiere columna updated_at fiable
--   - Backfill más complejo

-- fct_appointments con materialization incremental sería:
-- {{ config(materialized='incremental', unique_key='appointment_id',
--           incremental_strategy='merge') }}
-- ... WHERE updated_at > (SELECT MAX(updated_at) FROM {{ this }})


-- 9. Estimación de bytes procesados: comprobar antes de ejecutar queries caras.
--    En la consola de BigQuery: pegar query, mirar el validador en la esquina
--    superior derecha (estima bytes a procesar).
--    BQ cobra $5 por TB escaneado (on-demand). 10 GB ~ $0.05, 10 TB ~ $50.

-- Tamaño de las tablas:
SELECT
    table_name,
    ROUND(size_bytes / POW(1024, 3), 3)     AS size_gb,
    row_count
FROM `topd-lab.dbt_marts.__TABLES__`
ORDER BY size_bytes DESC;


-- 10. Window function vs subquery: comparación de performance.
--     Las window functions corren en un solo pass; las subqueries pueden rescanar.

-- MAL: subquery rescanea fct_appointments para obtener el max_date por paciente
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

-- BIEN: window function en un solo scan, QUALIFY elimina la subquery
SELECT patient_id, appointment_id, appointment_date
FROM `topd-lab.dbt_marts.fct_appointments`
WHERE status = 'completed'
QUALIFY ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY appointment_date DESC) = 1;
