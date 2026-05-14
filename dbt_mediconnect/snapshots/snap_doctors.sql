-- snap_doctors: captura SCD2 de la tabla de médicos.
--
-- Estrategia 'check': dbt compara los valores de check_cols entre la fila actual
-- y la última versión snapshotada. Si cambia alguno, cierra el row anterior
-- (dbt_valid_to) y abre una nueva versión (dbt_valid_from).
--
-- 'doctors' no tiene updated_at fiable (Faker no lo simula), por eso usamos
-- 'check' en vez de 'timestamp'. is_active y rating son los campos volátiles.

{% snapshot snap_doctors %}
{{
    config(
        target_schema='dbt_snapshots',
        unique_key='doctor_id',
        strategy='check',
        check_cols=['is_active', 'rating', 'years_experience', 'accepts_online_booking']
    )
}}

select
    doctor_id,
    full_name,
    specialty_id,
    country_id,
    city,
    created_at,
    is_active,
    rating,
    years_experience,
    accepts_online_booking
from {{ source('mediconnect', 'doctors') }}

{% endsnapshot %}
