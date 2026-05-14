-- STAGING: stg_doctors
-- Limpieza y tipado de la tabla cruda de médicos.
-- rating se redondea a 2 decimales para consistencia.

with source as (
    select * from {{ source('mediconnect', 'doctors') }}
),

renamed as (
    select
        doctor_id,
        full_name,
        specialty_id,
        country_id,
        city,
        cast(created_at as timestamp)           as created_at,
        cast(is_active as bool)                 as is_active,
        round(cast(rating as float64), 2)       as rating,
        cast(years_experience as int64)         as years_experience,
        cast(accepts_online_booking as bool)    as accepts_online_booking

    from source
)

select * from renamed
