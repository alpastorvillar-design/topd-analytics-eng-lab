-- MART CORE: dim_countries
-- DimensiÃ³n de paÃ­ses. Tabla pequeÃ±a y estable.

with countries as (
    select * from {{ ref('stg_countries') }}
)

select
    country_id,
    country_name,
    region,
    currency

from countries
