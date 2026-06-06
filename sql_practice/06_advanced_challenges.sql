-- 06_advanced_challenges.sql: retos SQL avanzados
-- Queries complejas que combinan múltiples técnicas: window functions,
-- CTEs encadenadas, aggregation avanzada y análisis de funnels.


-- 1. Médico con más ingresos en cada especialidad
-- Trampa habitual: GROUP BY + MAX no da el doctor_id correcto.
-- Solución: QUALIFY con RANK.
with doctor_revenue as (
    select
        p.doctor_id,
        d.full_name,
        p.specialty_id,
        s.specialty_name,
        SUM(p.amount_eur)  as total_revenue_eur
    from `topd-lab.dbt_marts.fct_payments`        as p
    join `topd-lab.dbt_marts.dim_doctors`         as d on p.doctor_id = d.doctor_id
    join `topd-lab.dbt_marts.dim_specialties`     as s on p.specialty_id = s.specialty_id
    where p.payment_status = 'paid'
    group by p.doctor_id, d.full_name, p.specialty_id, s.specialty_name
)
select specialty_id, specialty_name, doctor_id, full_name, total_revenue_eur
from doctor_revenue
qualify RANK() over (partition by specialty_id order by total_revenue_eur desc) = 1;


-- 2. Segundo médico más activo de cada país (variante N-ésimo mayor)
with doctor_activity as (
    select doctor_id, country_id, COUNT(*) as total_appointments
    from `topd-lab.dbt_marts.fct_appointments`
    where status = 'completed'
    group by doctor_id, country_id
)
select country_id, doctor_id, total_appointments
from doctor_activity
qualify DENSE_RANK() over (partition by country_id order by total_appointments desc) = 2
order by country_id;


-- 3. Pacientes activos en enero que no tuvieron cita en febrero
with january as (
    select distinct patient_id from `topd-lab.dbt_marts.fct_appointments`
    where appointment_date between '2024-01-01' and '2024-01-31'
      and status = 'completed'
),
february as (
    select distinct patient_id from `topd-lab.dbt_marts.fct_appointments`
    where appointment_date between '2024-02-01' and '2024-02-28'
      and status = 'completed'
)
select j.patient_id
from january as j
where not exists (select 1 from february as f where f.patient_id = j.patient_id);


-- 4. % que cada canal representa del total de citas
select
    channel,
    COUNT(*)                                            as appointments,
    SUM(COUNT(*)) over ()                               as total_appointments,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) over (), 2) as pct_of_total
from `topd-lab.dbt_marts.fct_appointments`
group by channel
order by appointments desc;


-- 5. Funnel completo: lead -> cita -> pago por canal de adquisición
-- VERSIÓN CORRECTA: anclada a la cohorte del lead (lead_date), no al mes del evento.
-- Así evitamos que pagos de meses anteriores inflen las tasas del mes actual.
-- fct_leads ya contiene los flags is_converted_to_appointment / is_converted_to_payment,
-- por lo que no necesitamos JOINs adicionales.
-- Se excluye el mes en curso porque los datos no están cerrados.
SELECT
    DATE_TRUNC(lead_date, MONTH)                         AS lead_month,
    lead_source,
    COUNT(DISTINCT lead_id)                              AS total_leads,
    COUNTIF(is_converted_to_appointment = TRUE)          AS converted_to_appointment,
    COUNTIF(is_converted_to_payment = TRUE)              AS converted_to_payment,
    ROUND(SAFE_DIVIDE(
        COUNTIF(is_converted_to_appointment = TRUE),
        COUNT(DISTINCT lead_id)
    ), 4)                                                AS lead_to_appt_rate,
    ROUND(SAFE_DIVIDE(
        COUNTIF(is_converted_to_payment = TRUE),
        COUNTIF(is_converted_to_appointment = TRUE)
    ), 4)                                                AS appt_to_payment_rate,
    ROUND(SAFE_DIVIDE(
        COUNTIF(is_converted_to_payment = TRUE),
        COUNT(DISTINCT lead_id)
    ), 4)                                                AS end_to_end_rate
FROM `topd-lab.dbt_marts.fct_leads`
WHERE lead_date < DATE_TRUNC(CURRENT_DATE(), MONTH)
GROUP BY lead_month, lead_source
ORDER BY lead_month, lead_source;


-- 6. Pacientes que volvieron dentro de los 90 días de su primera cita
with first_appointments as (
    select patient_id, MIN(appointment_date) as first_date
    from `topd-lab.dbt_marts.fct_appointments`
    where status = 'completed'
    group by patient_id
),
has_return as (
    select
        f.patient_id,
        f.first_date,
        MIN(a.appointment_date)     as second_date,
        DATE_DIFF(
            MIN(a.appointment_date), f.first_date, day
        ) <= 90                     as returned_within_90_days
    from first_appointments as f
    left join `topd-lab.dbt_marts.fct_appointments` as a
        on  a.patient_id     = f.patient_id
        and a.appointment_date > f.first_date
        and a.status         = 'completed'
    group by f.patient_id, f.first_date
)
select
    DATE_TRUNC(first_date, month)               as acquisition_month,
    COUNT(*)                                    as new_patients,
    COUNTIF(returned_within_90_days = TRUE)     as returned_in_90d,
    SAFE_DIVIDE(
        COUNTIF(returned_within_90_days = TRUE), COUNT(*)
    )                                           as return_rate
from has_return
group by acquisition_month
order by acquisition_month;


-- 7. Días desde la última cita por paciente + segmento de actividad.
-- Anclado a MAX(appointment_date) del dataset (2022-2024) en vez de
-- CURRENT_DATE() para que la segmentación tenga sentido sobre datos históricos.
with anchor as (
    select max(appointment_date) as anchor_date
    from `topd-lab.dbt_marts.fct_appointments`
    where status = 'completed'
)
select distinct
    f.patient_id,
    MAX(f.appointment_date) over (partition by f.patient_id) as last_appointment_date,
    DATE_DIFF(
        a.anchor_date,
        MAX(f.appointment_date) over (partition by f.patient_id),
        day
    )                                                    as days_since_last_visit,
    case
        when DATE_DIFF(a.anchor_date,
             MAX(f.appointment_date) over (partition by f.patient_id), day) <= 90
             then 'active'
        when DATE_DIFF(a.anchor_date,
             MAX(f.appointment_date) over (partition by f.patient_id), day) <= 365
             then 'at_risk'
        else 'churned'
    end                                                  as patient_segment
from `topd-lab.dbt_marts.fct_appointments` as f
cross join anchor as a
where f.status = 'completed'
order by days_since_last_visit desc;


-- 8. % de cada médico sobre el revenue total de su especialidad
with doctor_completed as (
    select doctor_id, specialty_id,
           COUNTIF(status = 'completed') as doc_completed
    from `topd-lab.dbt_marts.fct_appointments`
    group by doctor_id, specialty_id
),
specialty_total as (
    select specialty_id,
           COUNTIF(status = 'completed') as spec_completed
    from `topd-lab.dbt_marts.fct_appointments`
    group by specialty_id
)
select
    d.doctor_id,
    d.specialty_id,
    d.doc_completed,
    s.spec_completed,
    SAFE_DIVIDE(d.doc_completed, s.spec_completed) as pct_of_specialty
from doctor_completed as d
join specialty_total  as s using (specialty_id)
order by pct_of_specialty desc;
