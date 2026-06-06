-- 07_kpis_and_metrics.sql: KPIs de negocio y patrones de métrica
-- Revenue metrics, period-over-period growth, LTV, retención,
-- conversión de funnel, supply/demand. Todo contra la capa de marts.


-- 1. Core revenue KPIs con MoM, YoY y running total
with monthly_revenue as (
    select
        DATE_TRUNC(payment_date, month)                 as month,
        SUM(amount_eur)                                 as revenue_eur
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by month
)
select
    month,
    revenue_eur,
    LAG(revenue_eur, 1) over (order by month)           as prev_month_revenue,
    LAG(revenue_eur, 12) over (order by month)          as same_month_last_year,
    SAFE_DIVIDE(
        revenue_eur - LAG(revenue_eur, 1) over (order by month),
        LAG(revenue_eur, 1) over (order by month)
    )                                                   as mom_growth,
    SAFE_DIVIDE(
        revenue_eur - LAG(revenue_eur, 12) over (order by month),
        LAG(revenue_eur, 12) over (order by month)
    )                                                   as yoy_growth,
    SUM(revenue_eur) over (
        order by month
        rows between unbounded preceding and current row
    )                                                   as cumulative_revenue
from monthly_revenue
order by month;


-- 2. Revenue MTD, QTD, YTD anclados al máximo del dataset.
-- El dataset sintético cubre 2022-2024; usar CURRENT_DATE() dejaría las
-- ventanas vacías. anchor_date = último día con pago confirmado.
with anchor as (
    select max(payment_date) as anchor_date
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
)
select
    ROUND(SUM(case when p.payment_date >= DATE_TRUNC(a.anchor_date, month)
                   then p.amount_eur else 0 end), 2)    as revenue_mtd,
    ROUND(SUM(case when p.payment_date >= DATE_TRUNC(a.anchor_date, quarter)
                   then p.amount_eur else 0 end), 2)    as revenue_qtd,
    ROUND(SUM(case when p.payment_date >= DATE_TRUNC(a.anchor_date, year)
                   then p.amount_eur else 0 end), 2)    as revenue_ytd,
    ROUND(SUM(p.amount_eur), 2)                         as revenue_all_time
from `topd-lab.dbt_marts.fct_payments` as p
cross join anchor as a
where p.payment_status = 'paid';


-- 3. Completion rate, no-show rate, cancellation rate por canal y mes
select
    DATE_TRUNC(appointment_date, month)                 as month,
    channel,
    COUNT(*)                                            as total_appointments,
    COUNTIF(status = 'completed')                       as completed,
    COUNTIF(status = 'no_show')                         as no_show,
    COUNTIF(status = 'cancelled')                       as cancelled,
    ROUND(SAFE_DIVIDE(COUNTIF(status = 'completed'), COUNT(*)), 4)  as completion_rate,
    ROUND(SAFE_DIVIDE(COUNTIF(status = 'no_show'),   COUNT(*)), 4)  as no_show_rate,
    ROUND(SAFE_DIVIDE(COUNTIF(status = 'cancelled'), COUNT(*)), 4)  as cancellation_rate
from `topd-lab.dbt_marts.fct_appointments`
group by month, channel
order by month desc, total_appointments desc;


-- 4. LTV del paciente: revenue + frecuencia de citas + lifespan activo
with patient_revenue as (
    select
        a.patient_id,
        SUM(p.amount_eur)                               as total_revenue_eur,
        COUNT(distinct a.appointment_id)                as total_appointments,
        MIN(a.appointment_date)                         as first_appointment,
        MAX(a.appointment_date)                         as last_appointment,
        DATE_DIFF(MAX(a.appointment_date), MIN(a.appointment_date), month) as lifespan_months
    from `topd-lab.dbt_marts.fct_appointments` as a
    left join `topd-lab.dbt_marts.fct_payments` as p
        on a.appointment_id = p.appointment_id and p.payment_status = 'paid'
    where a.status = 'completed'
    group by a.patient_id
)
select
    patient_id,
    ROUND(total_revenue_eur, 2)                         as ltv_eur,
    total_appointments,
    lifespan_months,
    ROUND(SAFE_DIVIDE(total_revenue_eur, total_appointments), 2) as avg_revenue_per_visit,
    ROUND(SAFE_DIVIDE(total_appointments, NULLIF(lifespan_months, 0)), 2) as visits_per_month,
    NTILE(5) over (order by total_revenue_eur desc)     as ltv_quintile
from patient_revenue
order by ltv_eur desc;


-- 5. Funnel lead-to-revenue con conversión por etapa
-- NOTA: se usa is_converted_to_appointment (boolean) en vez de lead_status = 'converted'
-- porque lead_status no tiene valor 'converted' en este dataset; el flag booleano
-- es el campo fiable para identificar leads que convirtieron en cita.
with leads as (
    select DATE_TRUNC(lead_date, month) as month, COUNT(*) as total_leads
    from `topd-lab.dbt_marts.fct_leads`
    group by month
),
converted as (
    select DATE_TRUNC(lead_date, month) as month, COUNT(*) as converted_leads
    from `topd-lab.dbt_marts.fct_leads`
    where is_converted_to_appointment = TRUE
    group by month
),
paid as (
    select DATE_TRUNC(payment_date, month) as month, COUNT(*) as paid_appointments
    from `topd-lab.dbt_marts.fct_payments`
    where payment_status = 'paid'
    group by month
)
select
    l.month,
    l.total_leads,
    COALESCE(c.converted_leads, 0)                      as converted_leads,
    COALESCE(p.paid_appointments, 0)                    as paid_appointments,
    ROUND(SAFE_DIVIDE(c.converted_leads, l.total_leads), 4)             as lead_conversion_rate,
    ROUND(SAFE_DIVIDE(p.paid_appointments, c.converted_leads), 4)       as appt_to_payment_rate,
    ROUND(SAFE_DIVIDE(p.paid_appointments, l.total_leads), 4)           as end_to_end_rate
from leads as l
left join converted as c using (month)
left join paid      as p using (month)
order by l.month;


-- 6. Utilización de médicos: slots reservados vs capacidad disponible
--    Proxy: completed / (completed + no_show + cancelled) por mes.
select
    DATE_TRUNC(appointment_date, month)                 as month,
    d.specialty_id,
    COUNT(distinct a.doctor_id)                         as active_doctors,
    COUNT(*)                                            as total_slots,
    COUNTIF(a.status = 'completed')                     as completed_slots,
    ROUND(SAFE_DIVIDE(
        COUNTIF(a.status = 'completed'), COUNT(*)
    ), 4)                                               as utilisation_rate,
    ROUND(SAFE_DIVIDE(
        COUNT(*), COUNT(distinct a.doctor_id)
    ), 1)                                               as avg_appointments_per_doctor
from `topd-lab.dbt_marts.fct_appointments` as a
join `topd-lab.dbt_marts.dim_doctors`      as d using (doctor_id)
group by month, d.specialty_id
order by month desc, total_slots desc;


-- 7. Cohort retention: M0 a M6 en una sola query
with first_appt as (
    select patient_id, DATE_TRUNC(MIN(appointment_date), month) as cohort_month
    from `topd-lab.dbt_marts.fct_appointments`
    where status = 'completed'
    group by patient_id
),
activity as (
    select patient_id, DATE_TRUNC(appointment_date, month) as activity_month
    from `topd-lab.dbt_marts.fct_appointments`
    where status = 'completed'
    group by patient_id, activity_month
),
cohort_activity as (
    select
        f.cohort_month,
        DATE_DIFF(a.activity_month, f.cohort_month, month) as offset_month,
        COUNT(distinct f.patient_id)                        as retained
    from first_appt as f
    join activity   as a using (patient_id)
    where a.activity_month >= f.cohort_month
    group by f.cohort_month, offset_month
),
cohort_sizes as (
    select cohort_month, COUNT(*) as cohort_size
    from first_appt
    group by cohort_month
)
select
    ca.cohort_month,
    cs.cohort_size,
    MAX(case when offset_month = 0 then retained end)                   as m0,
    ROUND(MAX(case when offset_month = 1 then SAFE_DIVIDE(retained, cs.cohort_size) end), 4) as ret_m1,
    ROUND(MAX(case when offset_month = 2 then SAFE_DIVIDE(retained, cs.cohort_size) end), 4) as ret_m2,
    ROUND(MAX(case when offset_month = 3 then SAFE_DIVIDE(retained, cs.cohort_size) end), 4) as ret_m3,
    ROUND(MAX(case when offset_month = 4 then SAFE_DIVIDE(retained, cs.cohort_size) end), 4) as ret_m4,
    ROUND(MAX(case when offset_month = 5 then SAFE_DIVIDE(retained, cs.cohort_size) end), 4) as ret_m5,
    ROUND(MAX(case when offset_month = 6 then SAFE_DIVIDE(retained, cs.cohort_size) end), 4) as ret_m6
from cohort_activity as ca
join cohort_sizes    as cs using (cohort_month)
group by ca.cohort_month, cs.cohort_size
order by ca.cohort_month;


-- 8. Supply vs demand por especialidad y país
with demand as (
    select
        DATE_TRUNC(appointment_date, month)             as month,
        specialty_id,
        country_id,
        COUNT(*)                                        as appointments_requested,
        COUNT(distinct patient_id)                      as unique_patients
    from `topd-lab.dbt_marts.fct_appointments`
    group by month, specialty_id, country_id
),
supply as (
    select
        specialty_id,
        country_id,
        COUNT(distinct doctor_id)                       as active_doctors
    from `topd-lab.dbt_marts.dim_doctors`
    where is_active = TRUE
    group by specialty_id, country_id
)
select
    d.month,
    s.specialty_id,
    d.country_id,
    s.active_doctors,
    d.appointments_requested,
    d.unique_patients,
    ROUND(SAFE_DIVIDE(d.appointments_requested, s.active_doctors), 1) as demand_per_doctor
from demand as d
join supply as s using (specialty_id, country_id)
order by d.month desc, demand_per_doctor desc;
