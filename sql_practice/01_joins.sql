-- 01_joins.sql: JOINs aplicados al modelo de datos MediConnect
-- INNER, LEFT, FULL OUTER, SELF y anti-join (LEFT + WHERE IS NULL).


-- 1. INNER JOIN: citas con nombre de paciente y médico
select
    a.appointment_id,
    a.appointment_start_at,
    a.status,
    p.full_name   as patient_name,
    d.full_name   as doctor_name
from `topd-lab.dbt_marts.fct_appointments`    as a
inner join `topd-lab.dbt_marts.dim_patients`  as p using (patient_id)
inner join `topd-lab.dbt_marts.dim_doctors`   as d using (doctor_id)
where a.appointment_date >= '2023-01-01'
limit 100;


-- 2. LEFT JOIN: médicos con nº de citas completadas (incluye médicos con 0)
-- La condición de status va en ON, no en WHERE.
-- WHERE a.status = 'completed' convertiría el LEFT en INNER (filtraría NULLs).
select
    d.doctor_id,
    d.full_name,
    d.specialty_id,
    COUNT(a.appointment_id)  as completed_appointments
from `topd-lab.dbt_marts.dim_doctors` as d
left join `topd-lab.dbt_marts.fct_appointments` as a
    on  d.doctor_id = a.doctor_id
    and a.status    = 'completed'
group by d.doctor_id, d.full_name, d.specialty_id
order by completed_appointments desc;


-- 3. Anti-join: pagos sin cita correspondiente (detección de huérfanos)
select
    pay.payment_id,
    pay.appointment_id,
    pay.amount_cents
from `topd-lab.dbt_marts.fct_payments` as pay
left join `topd-lab.dbt_marts.fct_appointments` as a
    using (appointment_id)
where a.appointment_id is NULL;


-- 4. FULL OUTER JOIN: unir métricas de appointments y payments por día
-- Hay días con citas pero sin pagos (no_show/cancelled) y viceversa.
with daily_appts as (
    select
        appointment_date               as date,
        COUNT(*)                       as total_appointments
    from `topd-lab.dbt_marts.fct_appointments`
    group by appointment_date
),
daily_payments as (
    select
        payment_date                   as date,
        SUM(amount_eur)                as total_revenue_eur
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by payment_date
)
select
    COALESCE(a.date, p.date)           as date,
    COALESCE(a.total_appointments, 0)  as total_appointments,
    COALESCE(p.total_revenue_eur, 0)   as total_revenue_eur
from daily_appts    as a
full outer join daily_payments as p using (date)
order by date;


-- 5. SELF JOIN: pacientes que visitaron al mismo médico más de una vez
select
    a1.patient_id,
    a1.doctor_id,
    a1.appointment_id       as first_visit,
    a2.appointment_id       as repeat_visit,
    a1.appointment_start_at as first_date,
    a2.appointment_start_at as repeat_date
from `topd-lab.dbt_marts.fct_appointments` as a1
join `topd-lab.dbt_marts.fct_appointments` as a2
    on  a1.patient_id = a2.patient_id
    and a1.doctor_id  = a2.doctor_id
    and a1.appointment_start_at < a2.appointment_start_at
where a1.status = 'completed'
  and a2.status = 'completed'
order by a1.patient_id, first_date;


-- 6. JOIN con enriquecimiento dimensional: revenue por especialidad y país
select
    s.specialty_name,
    c.country_name,
    COUNT(distinct a.patient_id)        as unique_patients,
    COUNT(a.appointment_id)             as total_appointments,
    ROUND(SUM(p.amount_eur), 2)         as total_revenue_eur,
    SAFE_DIVIDE(
        SUM(p.amount_eur),
        COUNT(distinct a.patient_id)
    )                                   as revenue_per_patient
from `topd-lab.dbt_marts.fct_appointments`   as a
join `topd-lab.dbt_marts.fct_payments`       as p   using (appointment_id)
join `topd-lab.dbt_marts.dim_specialties`    as s   using (specialty_id)
join `topd-lab.dbt_marts.dim_countries`      as c   on c.country_id = a.country_id
where p.payment_status = 'paid'
group by s.specialty_name, c.country_name
order by total_revenue_eur desc;
