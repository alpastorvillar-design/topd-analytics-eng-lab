-- MART CORE: dim_specialties
-- DimensiÃ³n de especialidades mÃ©dicas. Tabla pequeÃ±a y estable.

with specialties as (
    select * from {{ ref('stg_specialties') }}
)

select
    specialty_id,
    specialty_name,
    specialty_group

from specialties
