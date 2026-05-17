-- STAGING: stg_leads
--
-- Un lead es un usuario interesado que aún no ha reservado cita.
-- patient_id y doctor_id pueden ser NULL (lead anónimo o sin médico concreto).
-- converted_appointment_id es NULL hasta que el lead convierte.

with source as (
    select * from {{ source('mediconnect', 'leads') }}
),

renamed as (
    select
        lead_id,
        patient_id,
        doctor_id,
        specialty_id,
        country_id,
        cast(created_at as timestamp)           as created_at,
        lower(lead_source)                      as lead_source,
        lower(lead_status)                      as lead_status,
        converted_appointment_id

    from source
)

select * from renamed
