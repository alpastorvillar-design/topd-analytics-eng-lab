-- MART CORE: dim_doctors
-- Dimensión de médicos con métricas de rendimiento pre-calculadas.

with doctors as (
    select * from {{ ref('stg_doctors') }}
),

performance as (
    select * from {{ ref('int_doctor_performance') }}
),

final as (
    select
        d.doctor_id,
        d.full_name,
        d.specialty_id,
        d.country_id,
        d.city,
        d.created_at,
        d.is_active,
        d.rating,
        d.years_experience,
        d.accepts_online_booking,

        -- Métricas de rendimiento
        coalesce(p.total_appointments, 0)               as total_appointments,
        coalesce(p.completed_appointments, 0)           as completed_appointments,
        coalesce(p.total_revenue_cents, 0)              as total_revenue_cents,
        {{ cents_to_euros('coalesce(p.total_revenue_cents, 0)') }} as total_revenue_eur,
        p.no_show_rate,
        p.completion_rate,
        p.distinct_patients,
        p.revenue_rank_in_specialty,
        p.first_appointment_date,
        p.last_appointment_date

    from doctors d
    left join performance p using (doctor_id)
)

select * from final
