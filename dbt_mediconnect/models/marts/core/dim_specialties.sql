-- MART CORE: dim_specialties
-- Dimensión de especialidades médicas. Tabla pequeña y estable.

with specialties as (
    select * from {{ ref('stg_specialties') }}
)

select
    specialty_id,
    specialty_name,
    specialty_group

from specialties
