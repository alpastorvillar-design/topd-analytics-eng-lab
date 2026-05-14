-- MART CORE: dim_countries
-- Dimensión de países. Tabla pequeña y estable.

with countries as (
    select * from {{ ref('stg_countries') }}
)

select
    country_id,
    country_name,
    region,
    currency

from countries
