-- STAGING: stg_appointments
--
-- Nota sobre NULLIF: cancellation_reason solo existe si status = 'cancelled'.
-- NULLIF('', '') -> NULL. Limpia strings vacÃ­os que Python puede generar.
--
-- Nota sobre is_first_appointment: viene como string '0'/'1' en algunos CSVs.
-- El CAST a BOOL maneja tanto booleanos nativos como integers.

with source as (
    select * from {{ source('mediconnect', 'appointments') }}
),

renamed as (
    select
        appointment_id,
        patient_id,
        doctor_id,
        cast(appointment_created_at as timestamp)   as appointment_created_at,
        cast(appointment_start_at as timestamp)     as appointment_start_at,
        cast(updated_at as timestamp)               as updated_at,
        lower(status)                               as status,
        lower(channel)                              as channel,
        nullif(cancellation_reason, '')             as cancellation_reason,
        cast(is_first_appointment as bool)          as is_first_appointment,
        source_lead_id

    from source
)

select * from renamed
