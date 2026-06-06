-- 08_advanced_patterns.sql: PIVOT, ARRAY, approximate aggregations
-- Patterns que aparecen en producción: pivot manual con agregación condicional,
-- ARRAY_AGG para anidar, STRUCT, APPROX functions,
-- EXCEPT/INTERSECT y date spine dinámico.


-- 1. Manual PIVOT: revenue mensual por canal en columnas.
--    BigQuery no tiene keyword PIVOT en sintaxis legacy; usamos conditional aggregation.
--
--    PASO PREVIO — verificar los valores reales de channel antes de ejecutar:
--    SELECT DISTINCT channel FROM `topd-lab.dbt_marts.fct_appointments` ORDER BY 1;
--    Actualizar las columnas del CASE WHEN con los valores que devuelva esa query.
--
--    Ejemplo con valores genéricos (ajustar a los valores reales del dataset):
select
    DATE_TRUNC(p.payment_date, month)                             as month,
    ROUND(SUM(case when a.channel = 'online' then p.amount_eur else 0 end), 2) as online_revenue,
    ROUND(SUM(case when a.channel = 'app'    then p.amount_eur else 0 end), 2) as app_revenue,
    ROUND(SUM(case when a.channel = 'phone'  then p.amount_eur else 0 end), 2) as phone_revenue,
    ROUND(SUM(case when a.channel = 'clinic' then p.amount_eur else 0 end), 2) as clinic_revenue,
    ROUND(SUM(p.amount_eur), 2)                                   as total_revenue
from `topd-lab.dbt_marts.fct_payments`      as p
join `topd-lab.dbt_marts.fct_appointments`  as a using (appointment_id)
where p.payment_status = 'paid'
group by month
order by month;


-- 2. Manual PIVOT: convertir la tabla long de retencion a columnas M+1..M+6.
--    mart_patient_retention ya esta en formato long para BI y heatmaps.
select
    cohort_month,
    cohort_size,
    MAX(case when months_since_acquisition = 1 then retention_rate end) as retention_m1,
    MAX(case when months_since_acquisition = 2 then retention_rate end) as retention_m2,
    MAX(case when months_since_acquisition = 3 then retention_rate end) as retention_m3,
    MAX(case when months_since_acquisition = 4 then retention_rate end) as retention_m4,
    MAX(case when months_since_acquisition = 5 then retention_rate end) as retention_m5,
    MAX(case when months_since_acquisition = 6 then retention_rate end) as retention_m6
from `topd-lab.dbt_marts.mart_patient_retention`
where months_since_acquisition between 1 and 6
group by cohort_month, cohort_size
order by cohort_month;


-- 3. ARRAY_AGG: agregar filas hijas como array dentro de la fila padre.
--    Una fila por paciente con todos sus appointment_id como array.
select
    a.patient_id,
    COUNT(*)                                            as total_appointments,
    ARRAY_AGG(
        STRUCT(a.appointment_id, a.appointment_date, a.status, a.amount_eur)
        order by a.appointment_date
    )                                                   as appointments
from `topd-lab.dbt_marts.fct_appointments` as a
where a.status = 'completed'
group by a.patient_id
limit 10;


-- 4. UNNEST de arrays: una fila por especialidad por médico.
--    Hipotético: si doctors.specialties fuera ARRAY<STRING>.
select
    d.doctor_id,
    d.full_name,
    specialty_tag
from `topd-lab.dbt_marts.dim_doctors` as d
cross join UNNEST(['cardiology', 'general', 'pediatrics']) as specialty_tag
-- En la práctica: CROSS JOIN UNNEST(d.specialty_tags) AS specialty_tag
limit 20;


-- 5. APPROX functions: aggregations más rápidas sobre tablas grandes.
--    APPROX_COUNT_DISTINCT usa HyperLogLog (~2% error, 10-100x más rápido).
select
    DATE_TRUNC(a.appointment_date, month)               as month,
    COUNT(distinct a.patient_id)                        as exact_unique_patients,
    APPROX_COUNT_DISTINCT(a.patient_id)                 as approx_unique_patients,
    APPROX_QUANTILES(a.amount_eur, 4)                   as revenue_quartiles
from `topd-lab.dbt_marts.fct_appointments` as a
group by month
order by month;


-- 6. EXCEPT / INTERSECT: operaciones de conjunto para overlap de pacientes.
-- Pacientes que reservaron online pero nunca por teléfono:
select patient_id from `topd-lab.dbt_marts.fct_appointments` where channel = 'web'
except distinct
select patient_id from `topd-lab.dbt_marts.fct_appointments` where channel = 'phone';

-- Pacientes que usaron web y teléfono:
select patient_id from `topd-lab.dbt_marts.fct_appointments` where channel = 'web'
intersect distinct
select patient_id from `topd-lab.dbt_marts.fct_appointments` where channel = 'phone';


-- 7. Date spine con LEFT JOIN: zero-fill de días sin datos en time series.
with spine as (
    select d as date
    from UNNEST(
        GENERATE_DATE_ARRAY('2024-01-01', '2024-12-31', interval 1 day)
    ) as d
),
daily_revenue as (
    select
        payment_date,
        SUM(amount_eur)                                 as revenue_eur,
        COUNT(*)                                        as payments
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
      and payment_date between '2024-01-01' and '2024-12-31'
    group by payment_date
)
select
    s.date,
    COALESCE(r.revenue_eur, 0)                          as revenue_eur,
    COALESCE(r.payments, 0)                             as payments,
    -- 7-day rolling average
    AVG(COALESCE(r.revenue_eur, 0)) over (
        order by s.date
        rows between 6 preceding and current row
    )                                                   as revenue_7d_avg
from spine as s
left join daily_revenue as r on s.date = r.payment_date
order by s.date;


-- 8. Recursive CTE: month spine dinamico para gap filling.
--    BigQuery soporta recursive CTEs desde 2022 (GA).
with recursive month_spine as (
    select
        date '2022-01-01' as month

    union all

    select DATE_ADD(month, interval 1 month)
    from month_spine
    where month < date '2024-12-01'
),
monthly_revenue as (
    select
        DATE_TRUNC(payment_date, month) as month,
        SUM(amount_eur)                 as revenue_eur
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by month
)
select
    s.month,
    COALESCE(r.revenue_eur, 0) as revenue_eur
from month_spine as s
left join monthly_revenue as r using (month)
order by s.month;


-- 9. STRING_AGG: concatenar valores dentro de un grupo.
-- Especialidades visitadas por cada paciente como string separado por comas:
select
    patient_id,
    COUNT(distinct specialty_id)                        as distinct_specialties,
    STRING_AGG(distinct s.specialty_name order by s.specialty_name) as specialties_visited
from `topd-lab.dbt_marts.fct_appointments` as a
join `topd-lab.dbt_marts.dim_specialties`  as s using (specialty_id)
where a.status = 'completed'
group by patient_id
having COUNT(distinct specialty_id) > 1
order by distinct_specialties desc
limit 20;


-- 10. Percentile / median revenue por especialidad con APPROX_QUANTILES.
select
    s.specialty_name,
    COUNT(*)                                                as total_payments,
    ROUND(AVG(p.amount_eur), 2)                             as avg_revenue,
    APPROX_QUANTILES(p.amount_eur, 100)[OFFSET(50)]         as median_revenue,
    APPROX_QUANTILES(p.amount_eur, 100)[OFFSET(25)]         as p25_revenue,
    APPROX_QUANTILES(p.amount_eur, 100)[OFFSET(75)]         as p75_revenue,
    APPROX_QUANTILES(p.amount_eur, 100)[OFFSET(95)]         as p95_revenue
from `topd-lab.dbt_marts.fct_payments`    as p
join `topd-lab.dbt_marts.dim_specialties` as s
    on p.specialty_id = s.specialty_id
where p.payment_status = 'paid'
group by s.specialty_name
order by median_revenue desc;
