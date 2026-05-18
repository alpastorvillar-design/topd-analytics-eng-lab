-- snap_patients: captura SCD2 de la tabla de pacientes.
--
-- Estrategia 'check': dbt compara los valores de check_cols entre la fila actual
-- y la última versión snapshotada. Si cambia alguno, cierra el row anterior
-- (dbt_valid_to) y abre una nueva versión (dbt_valid_from).
--
-- Permite responder preguntas históricas como "¿cuántos pacientes activos
-- teníamos en un mes concreto?" aunque la tabla actual ya no lo refleje.

{% snapshot snap_patients %}
{{
    config(
        target_schema='dbt_snapshots',
        unique_key='patient_id',
        strategy='check',
        check_cols=['is_active', 'city', 'country_id', 'acquisition_channel']
    )
}}

select
    patient_id,
    full_name,
    gender,
    birth_date,
    country_id,
    city,
    created_at,
    acquisition_channel,
    is_active
from {{ source('mediconnect', 'patients') }}

{% endsnapshot %}
