-- INTERMEDIATE: int_doctor_performance
-- Métricas agregadas por médico: volumen, tasas de completado/cancelación,
-- revenue y ranking dentro de especialidad (RANK para respetar empates).

with appointments as (
    select * from {{ ref('int_appointments_enriched') }}
),

doctors as (
    select * from {{ ref('stg_doctors') }}
),

doctor_metrics as (
    select
        a.doctor_id,

        count(*)                                            as total_appointments,
        countif(a.status = 'completed')                    as completed_appointments,
        countif(a.status = 'cancelled')                    as cancelled_appointments,
        countif(a.status = 'no_show')                      as no_show_appointments,

        round(safe_divide(
            countif(a.status = 'no_show'),
            count(*)
        ), 4)                                               as no_show_rate,

        round(safe_divide(
            countif(a.status = 'completed'),
            count(*)
        ), 4)                                               as completion_rate,

        sum(case when a.payment_status = 'paid'
            then a.amount_cents else 0 end)                as total_revenue_cents,

        count(distinct a.patient_id)                       as distinct_patients,
        count(distinct date_trunc(
            date(a.appointment_start_at), month)
        )                                                   as active_months,

        min(date(a.appointment_start_at))                  as first_appointment_date,
        max(date(a.appointment_start_at))                  as last_appointment_date

    from appointments a
    group by a.doctor_id
),

final as (
    select
        d.doctor_id,
        d.specialty_id,
        d.country_id,
        d.rating,
        d.years_experience,
        d.accepts_online_booking,
        d.is_active,

        m.total_appointments,
        m.completed_appointments,
        m.cancelled_appointments,
        m.no_show_appointments,
        m.no_show_rate,
        m.completion_rate,
        m.total_revenue_cents,
        m.distinct_patients,
        m.active_months,
        m.first_appointment_date,
        m.last_appointment_date,

        -- Ranking de ingresos dentro de la especialidad
        rank() over (
            partition by d.specialty_id
            order by m.total_revenue_cents desc
        )                                                   as revenue_rank_in_specialty

    from doctors d
    left join doctor_metrics m using (doctor_id)
)

select * from final
