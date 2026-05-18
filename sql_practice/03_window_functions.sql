-- 03_window_functions.sql: Window Functions
-- ROW_NUMBER / RANK / DENSE_RANK, LAG/LEAD, SUM OVER frames, FIRST/LAST_VALUE,
-- NTILE, QUALIFY. Sin colapsar filas, a diferencia de GROUP BY.


-- 1. ROW_NUMBER: numerar visitas de cada paciente por fecha
select
    patient_id,
    appointment_id,
    appointment_start_at,
    status,
    ROW_NUMBER() over (
        partition by patient_id
        order by appointment_start_at
    )                                       as visit_number
from `topd-lab.dbt_marts.fct_appointments`
where status = 'completed'
order by patient_id, visit_number;


-- 2. RANK vs DENSE_RANK vs ROW_NUMBER
-- Con empates:
--   ROW_NUMBER -> 1,2,3,4 (siempre único)
--   RANK       -> 1,2,2,4 (salta número)
--   DENSE_RANK -> 1,2,2,3 (sin salto)
select
    specialty_id,
    month,
    total_revenue_eur,
    RANK()       over (partition by month order by total_revenue_eur desc) as rnk,
    DENSE_RANK() over (partition by month order by total_revenue_eur desc) as dense_rnk,
    ROW_NUMBER() over (partition by month order by total_revenue_eur desc) as row_num
from `topd-lab.dbt_marts.agg_specialty_performance`
order by month, rnk;


-- 3. LAG / LEAD: días entre citas consecutivas del mismo paciente
select
    patient_id,
    appointment_id,
    appointment_start_at                                    as current_appt,
    LAG(appointment_start_at) over (
        partition by patient_id
        order by appointment_start_at
    )                                                       as previous_appt,
    DATE_DIFF(
        DATE(appointment_start_at),
        DATE(LAG(appointment_start_at) over (
            partition by patient_id
            order by appointment_start_at
        )),
        day
    )                                                       as days_since_last_visit
from `topd-lab.dbt_marts.fct_appointments`
where status = 'completed'
order by patient_id, current_appt;


-- 4. SUM OVER: revenue acumulado (running total) y ventana rolling 7 días
with daily as (
    select payment_date, SUM(amount_eur) as daily_revenue
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by payment_date
)
select
    payment_date,
    daily_revenue,
    SUM(daily_revenue) over (
        order by payment_date
        rows between unbounded preceding and current row
    )                        as cumulative_revenue,
    SUM(daily_revenue) over (
        order by payment_date
        rows between 6 preceding and current row
    )                        as revenue_last_7_days
from daily
order by payment_date;


-- 5. FIRST_VALUE / LAST_VALUE: primera y última cita de cada paciente
-- LAST_VALUE necesita frame explícito; sin él usa RANGE BETWEEN UNBOUNDED
-- PRECEDING AND CURRENT ROW y devuelve la fila actual, no la última.
select distinct
    patient_id,
    FIRST_VALUE(appointment_id) over (
        partition by patient_id
        order by appointment_start_at
        rows between unbounded preceding and unbounded following
    )                           as first_appointment_id,
    LAST_VALUE(appointment_id) over (
        partition by patient_id
        order by appointment_start_at
        rows between unbounded preceding and unbounded following
    )                           as last_appointment_id
from `topd-lab.dbt_marts.fct_appointments`
where status = 'completed';


-- 6. NTILE: segmentar médicos en cuartiles por revenue
with doctor_revenue as (
    select doctor_id, SUM(amount_eur) as total_revenue
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by doctor_id
)
select
    doctor_id,
    total_revenue,
    NTILE(4) over (order by total_revenue desc)  as revenue_quartile
    -- 1 = top 25%, 4 = bottom 25%
from doctor_revenue
order by revenue_quartile, total_revenue desc;


-- 7. QUALIFY: filtrar por window function sin subquery (BigQuery / Snowflake)
-- Equivalente PostgreSQL requiere subquery o CTE.

-- Cita más reciente de cada paciente:
select patient_id, appointment_id, appointment_start_at, status
from `topd-lab.dbt_marts.fct_appointments`
qualify ROW_NUMBER() over (
    partition by patient_id
    order by appointment_start_at desc
) = 1;

-- % del total por canal usando SUM OVER sin PARTITION BY:
select
    channel,
    COUNT(*)                                        as appointments,
    SUM(COUNT(*)) over ()                           as total_appointments,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) over (), 2) as pct_of_total
from `topd-lab.dbt_marts.fct_appointments`
group by channel
order by appointments desc;
