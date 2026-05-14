-- MART EXECUTIVE: agg_specialty_performance
-- Rendimiento por especialidad médica. Para identificar top/bottom performers.

with appointments as (
    select
        date_trunc(appointment_date, month)     as month,
        specialty_id,
        count(*)                                as total_appointments,
        countif(status = 'completed')           as completed_appointments,
        countif(status = 'no_show')             as no_show_appointments,
        count(distinct patient_id)              as unique_patients,
        count(distinct doctor_id)               as active_doctors,
        sum(amount_eur)                         as total_revenue_eur
    from {{ ref('fct_appointments') }}
    group by month, specialty_id
),

specialties as (
    select specialty_id, specialty_name, specialty_group
    from {{ ref('dim_specialties') }}
),

final as (
    select
        a.month,
        a.specialty_id,
        s.specialty_name,
        s.specialty_group,
        a.total_appointments,
        a.completed_appointments,
        a.no_show_appointments,
        a.unique_patients,
        a.active_doctors,
        coalesce(a.total_revenue_eur, 0)        as total_revenue_eur,

        safe_divide(
            a.completed_appointments,
            a.total_appointments
        )                                       as completion_rate,

        safe_divide(
            a.total_appointments,
            a.active_doctors
        )                                       as appointments_per_doctor,

        rank() over (
            partition by a.month
            order by coalesce(a.total_revenue_eur, 0) desc
        )                                       as specialty_revenue_rank

    from appointments a
    left join specialties s using (specialty_id)
)

select * from final
