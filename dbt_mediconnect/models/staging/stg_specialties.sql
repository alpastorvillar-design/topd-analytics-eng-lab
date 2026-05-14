-- STAGING: stg_specialties
-- Tabla de referencia pequeña. Sin lógica especial, solo limpieza de tipos.

with source as (
    select * from {{ source('mediconnect', 'specialties') }}
),

renamed as (
    select
        specialty_id,
        specialty_name,
        specialty_group

    from source
)

select * from renamed
