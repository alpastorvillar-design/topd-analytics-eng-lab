-- MART PRODUCT: mart_appointment_quality
-- MÃ©tricas de calidad de citas por canal, especialidad y paÃ­s.
-- Identifica dÃ³nde se concentran no-shows y cancelaciones.

with appointments as (
    select * from {{ ref('fct_appointments') }}
),

final as (
    select
        date_trunc(appointment_date, month)         as month,
        channel,
        specialty_id,
        country_id,

        count(*)                                    as total_appointments,
        countif(status = 'completed')               as completed,
        countif(status = 'cancelled')               as cancelled,
        countif(status = 'no_show')                 as no_show,
        countif(status = 'scheduled')               as scheduled,

        safe_divide(
            countif(status = 'completed'), count(*)
        )                                           as completion_rate,

        safe_divide(
            countif(status = 'no_show'), count(*)
        )                                           as no_show_rate,

        safe_divide(
            countif(status = 'cancelled'), count(*)
        )                                           as cancellation_rate,

        -- Primer canal con mÃ¡s no-shows (Ãºtil para priorizar mejoras)
        avg(doctor_rating)                          as avg_doctor_rating

    from appointments
    group by month, channel, specialty_id, country_id
)

select * from final
