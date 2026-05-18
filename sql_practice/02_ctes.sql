-- 02_ctes.sql: CTEs y subqueries
-- CTE vs subquery, CTEs encadenadas (patrón dbt), NOT EXISTS,
-- series de fechas con GENERATE_DATE_ARRAY, QUALIFY con subquery inline.


-- 1. CTE vs subquery

-- Con subquery anidada (difícil de mantener):
select doctor_id, total_revenue
from (
    select doctor_id, SUM(amount_eur) as total_revenue
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by doctor_id
)
where total_revenue > 5000;

-- Con CTE (mismo resultado, más legible):
with doctor_revenue as (
    select
        doctor_id,
        SUM(amount_eur)  as total_revenue
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by doctor_id
)
select doctor_id, total_revenue
from doctor_revenue
where total_revenue > 5000
order by total_revenue desc;


-- 2. CTEs encadenadas: pipeline de transformaciones (patrón dbt)
with

appointments_enriched as (
    select
        a.appointment_id,
        a.patient_id,
        a.doctor_id,
        a.appointment_date,
        a.specialty_id,
        a.country_id,
        a.channel,
        p.full_name      as patient_name,
        d.full_name      as doctor_name,
        s.specialty_name
    from `topd-lab.dbt_marts.fct_appointments`   as a
    join `topd-lab.dbt_marts.dim_patients`       as p using (patient_id)
    join `topd-lab.dbt_marts.dim_doctors`        as d using (doctor_id)
    join `topd-lab.dbt_marts.dim_specialties`    as s using (specialty_id)
    where a.status = 'completed'
),

doctor_specialty_summary as (
    select
        doctor_id,
        doctor_name,
        specialty_name,
        COUNT(*)                        as completed_appointments,
        COUNT(distinct patient_id)      as unique_patients,
        COUNT(distinct appointment_date) as active_days
    from appointments_enriched
    group by doctor_id, doctor_name, specialty_name
),

doctor_revenue as (
    select
        a.doctor_id,
        SUM(p.amount_eur)               as total_revenue_eur
    from appointments_enriched          as a
    join `topd-lab.dbt_marts.fct_payments` as p using (appointment_id)
    where p.payment_status = 'paid'
    group by a.doctor_id
)

select
    s.doctor_id,
    s.doctor_name,
    s.specialty_name,
    s.completed_appointments,
    s.unique_patients,
    s.active_days,
    COALESCE(r.total_revenue_eur, 0)    as total_revenue_eur,
    SAFE_DIVIDE(
        COALESCE(r.total_revenue_eur, 0),
        s.completed_appointments
    )                                   as avg_revenue_per_appointment
from doctor_specialty_summary   as s
left join doctor_revenue        as r using (doctor_id)
order by total_revenue_eur desc;


-- 3. NOT EXISTS frente a NOT IN cuando puede haber NULLs
-- NOT IN devuelve 0 filas si la subquery contiene algún NULL.
-- NOT EXISTS es seguro con NULLs y generalmente más eficiente.

-- Pacientes que nunca han completado una cita:
select patient_id, full_name
from `topd-lab.dbt_marts.dim_patients`
where not exists (
    select 1
    from `topd-lab.dbt_marts.fct_appointments`
    where fct_appointments.patient_id = dim_patients.patient_id
      and status = 'completed'
);


-- 4. Generar serie de fechas (dos enfoques)

-- Opción A: CTE recursiva (compatible con PostgreSQL)
with recursive date_series as (
    select date '2023-01-01' as d
    union all
    select DATE_ADD(d, interval 1 day)
    from date_series
    where d < date '2023-01-31'
)
select d from date_series;

-- Opción B: GENERATE_DATE_ARRAY (BigQuery, más eficiente)
select d
from UNNEST(
    GENERATE_DATE_ARRAY('2023-01-01', '2023-12-31', interval 1 day)
) as d;

-- Uso práctico: asegurar fila por día aunque no haya revenue ese día
with all_dates as (
    select d as date
    from UNNEST(GENERATE_DATE_ARRAY('2023-01-01', '2023-12-31', interval 1 day)) as d
),
daily_revenue as (
    select payment_date, SUM(amount_eur) as revenue_eur
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by payment_date
)
select
    d.date,
    COALESCE(r.revenue_eur, 0)  as revenue_eur
from all_dates as d
left join daily_revenue as r on d.date = r.payment_date
order by d.date;


-- 5. Canal con más no-shows por especialidad (QUALIFY + subquery inline)
select
    specialty_id,
    channel,
    no_show_count,
    total_count,
    SAFE_DIVIDE(no_show_count, total_count) as no_show_rate
from (
    select
        specialty_id,
        channel,
        COUNTIF(status = 'no_show')         as no_show_count,
        COUNT(*)                            as total_count
    from `topd-lab.dbt_marts.fct_appointments`
    group by specialty_id, channel
)
qualify RANK() over (
    partition by specialty_id
    order by no_show_count desc
) = 1
order by specialty_id;
