-- MART PRODUCT: mart_doctor_supply_demand
-- Oferta (mÃ©dicos activos) vs demanda (citas) por especialidad, paÃ­s y mes.
-- Detecta desequilibrios: especialidades con mÃ¡s demanda que mÃ©dicos disponibles.

with appointments as (
    select
        specialty_id,
        country_id,
        date_trunc(appointment_date, month)     as month,
        count(*)                                as total_appointments,
        countif(status = 'completed')           as completed_appointments,
        countif(status = 'no_show')             as no_show_appointments,
        count(distinct doctor_id)               as active_doctors_with_appointments
    from {{ ref('fct_appointments') }}
    group by specialty_id, country_id, month
),

doctors as (
    select
        specialty_id,
        country_id,
        countif(is_active = true)               as total_active_doctors,
        avg(rating)                             as avg_doctor_rating,
        avg(years_experience)                   as avg_years_experience
    from {{ ref('dim_doctors') }}
    group by specialty_id, country_id
),

final as (
    select
        a.specialty_id,
        a.country_id,
        a.month,
        a.total_appointments,
        a.completed_appointments,
        a.no_show_appointments,
        a.active_doctors_with_appointments,
        d.total_active_doctors,
        d.avg_doctor_rating,
        d.avg_years_experience,

        -- Ratio demanda/oferta: >1 significa mÃ¡s citas que mÃ©dicos activos ese mes
        safe_divide(
            a.total_appointments,
            d.total_active_doctors
        )                                       as appointments_per_doctor,

        safe_divide(
            a.no_show_appointments,
            a.total_appointments
        )                                       as no_show_rate

    from appointments a
    left join doctors d using (specialty_id, country_id)
)

select * from final
