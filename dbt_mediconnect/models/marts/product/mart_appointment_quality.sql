-- MART PRODUCT: mart_appointment_quality
-- Métricas de calidad de citas por canal, especialidad y país.
-- Identifica dónde se concentran no-shows y cancelaciones.

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

        round(safe_divide(
            countif(status = 'completed'), count(*)
        ), 4)                                       as completion_rate,

        round(safe_divide(
            countif(status = 'no_show'), count(*)
        ), 4)                                       as no_show_rate,

        round(safe_divide(
            countif(status = 'cancelled'), count(*)
        ), 4)                                       as cancellation_rate,

        round(avg(doctor_rating), 2)                as avg_doctor_rating

    from appointments
    group by month, channel, specialty_id, country_id
)

select * from final
