-- STAGING: stg_patients
-- Limpieza de tipos sobre raw_mediconnect.patients.
-- Sin joins ni lógica de negocio - eso va en intermediate.
-- VIEW: no duplica almacenamiento, siempre refleja el raw actualizado.

with source as (
    select * from {{ source('mediconnect', 'patients') }}
),

renamed as (
    select
        patient_id,
        full_name,
        gender,
        -- CAST asegura el tipo correcto independientemente de cómo llegó el CSV
        cast(birth_date as date)        as birth_date,
        country_id,
        city,
        cast(created_at as timestamp)   as created_at,
        lower(acquisition_channel)      as acquisition_channel,
        cast(is_active as bool)         as is_active

    from source
)

select * from renamed
