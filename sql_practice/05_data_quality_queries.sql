-- 05_data_quality_queries.sql: queries de calidad de datos
-- Patrones SQL para detectar duplicados, NULLs, orphan records, valores
-- fuera de rango e inconsistencias de negocio. Mismos patrones que los
-- dbt singular tests.


-- 1. Unicidad de PKs
-- Un resultado vacío = sin duplicados (el check pasa).
select appointment_id, COUNT(*) as n
from `topd-lab.dbt_marts.fct_appointments`
group by appointment_id
having n > 1;

-- Versión rápida con window function (más eficiente en tablas grandes):
select appointment_id
from `topd-lab.dbt_marts.fct_appointments`
qualify COUNT(*) over (partition by appointment_id) > 1;


-- 2. Integridad referencial
-- Citas con patient_id que no existe en dim_patients:
select a.appointment_id, a.patient_id
from `topd-lab.dbt_marts.fct_appointments` as a
left join `topd-lab.dbt_marts.dim_patients` as p using (patient_id)
where p.patient_id is NULL;

-- Pagos sin cita correspondiente:
select pay.payment_id, pay.appointment_id
from `topd-lab.dbt_marts.fct_payments` as pay
left join `topd-lab.dbt_marts.fct_appointments` as a using (appointment_id)
where a.appointment_id is NULL;


-- 3. Valores aceptados
select distinct status
from `topd-lab.dbt_marts.fct_appointments`
where status not in ('completed', 'cancelled', 'no_show', 'scheduled');

select distinct payment_status
from `topd-lab.dbt_marts.fct_payments`
where payment_status not in ('paid', 'refunded', 'failed', 'pending');


-- 4. Rangos y coherencia temporal
-- amount_cents debe ser positivo:
select payment_id, amount_cents
from `topd-lab.dbt_marts.fct_payments`
where amount_cents <= 0;

-- appointment_created_at debe ser anterior a appointment_start_at:
select appointment_id, appointment_created_at, appointment_start_at
from `topd-lab.dbt_marts.fct_appointments`
where appointment_created_at >= appointment_start_at;

-- Pagos no deben tener fecha anterior a la cita:
select p.payment_id, p.payment_created_at, a.appointment_start_at
from `topd-lab.dbt_marts.fct_payments`    as p
join `topd-lab.dbt_marts.fct_appointments` as a using (appointment_id)
where p.payment_created_at < a.appointment_start_at;

-- Fechas de cita fuera del rango esperado del dataset:
select COUNT(*) as out_of_range
from `topd-lab.dbt_marts.fct_appointments`
where appointment_date < '2022-01-01'
   or appointment_date > CURRENT_DATE();


-- 5. Reglas de negocio específicas
-- Solo las citas 'completed' deben tener pagos:
select a.appointment_id, a.status, p.payment_id
from `topd-lab.dbt_marts.fct_payments`     as p
join `topd-lab.dbt_marts.fct_appointments` as a using (appointment_id)
where a.status != 'completed';

-- Leads convertidos deben tener appointment_id válido:
select lead_id, appointment_id
from `topd-lab.dbt_marts.fct_leads` as l
left join `topd-lab.dbt_marts.fct_appointments` as a
    on l.appointment_id = a.appointment_id
where l.is_converted_to_appointment = TRUE
  and a.appointment_id is NULL;


-- 6. Distribución de NULLs por columna (auditoría rápida)
select
    COUNTIF(patient_id           is NULL) as null_patient_id,
    COUNTIF(doctor_id            is NULL) as null_doctor_id,
    COUNTIF(appointment_date     is NULL) as null_appointment_date,
    COUNTIF(status               is NULL) as null_status,
    COUNTIF(cancellation_reason  is NULL) as null_cancellation_reason,
    COUNT(*)                              as total_rows
from `topd-lab.dbt_marts.fct_appointments`;


-- 7. Análisis de cohortes: retención de pacientes
with patient_cohorts as (
    select
        patient_id,
        DATE_TRUNC(MIN(appointment_date), month)  as cohort_month
    from `topd-lab.dbt_marts.fct_appointments`
    where status = 'completed'
    group by patient_id
),
patient_activity as (
    select patient_id, DATE_TRUNC(appointment_date, month) as activity_month
    from `topd-lab.dbt_marts.fct_appointments`
    where status = 'completed'
    group by patient_id, activity_month
),
cohort_data as (
    select
        c.patient_id,
        c.cohort_month,
        DATE_DIFF(a.activity_month, c.cohort_month, month) as months_since_acquisition
    from patient_cohorts  as c
    join patient_activity as a using (patient_id)
    where a.activity_month >= c.cohort_month
),
cohort_sizes as (
    select cohort_month, COUNT(distinct patient_id) as cohort_size
    from patient_cohorts
    group by cohort_month
)
select
    cd.cohort_month,
    cd.months_since_acquisition,
    cs.cohort_size,
    COUNT(distinct cd.patient_id)           as retained_patients,
    SAFE_DIVIDE(
        COUNT(distinct cd.patient_id),
        cs.cohort_size
    )                                       as retention_rate
from cohort_data      as cd
join cohort_sizes     as cs using (cohort_month)
group by cd.cohort_month, cd.months_since_acquisition, cs.cohort_size
order by cd.cohort_month, cd.months_since_acquisition;


-- 8. MoM growth del revenue
with monthly as (
    select
        DATE_TRUNC(payment_date, month)  as month,
        SUM(amount_eur)                  as revenue_eur
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by month
)
select
    month,
    revenue_eur,
    LAG(revenue_eur) over (order by month)  as prev_month_revenue,
    ROUND(100.0 * SAFE_DIVIDE(
        revenue_eur - LAG(revenue_eur) over (order by month),
        LAG(revenue_eur) over (order by month)
    ), 2)                                   as mom_growth_pct
from monthly
order by month;
