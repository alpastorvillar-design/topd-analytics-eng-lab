-- STAGING: stg_countries
-- Catálogo de países. Tabla pequeña y estática.

with source as (
    select * from {{ source('mediconnect', 'countries') }}
),

renamed as (
    select
        country_id,
        country_name,
        region,
        currency

    from source
)

select * from renamed
