-- MART CORE: fct_appointments
--
-- Tabla de hechos de citas. Corazón del modelo dimensional.
-- Una fila por cita. Contiene métricas numéricas y FKs a dimensiones.
--
-- PARTICIONADO por appointment_date:
-- BigQuery escanea solo las particiones que coinciden con el filtro WHERE.
-- Si filtras por fecha (lo más común en dashboards), reduces bytes escaneados
-- hasta en un 99%. Coste directo.
--
-- CLUSTERIZADO por country_id, specialty_id, status:
-- Dentro de cada partición, BigQuery ordena físicamente los datos por estos
-- campos. Las queries con filtros en estas columnas son más rápidas y baratas.
--
-- Partición: columna de fecha con filtros frecuentes de rango temporal.
-- Clustering: columnas de alta cardinalidad usadas en WHERE o GROUP BY.

{{
    config(
        materialized='table',
        partition_by={
            'field': 'appointment_date',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['country_id', 'specialty_id', 'status']
    )
}}

with appointments as (
    select * from {{ ref('int_appointments_enriched') }}
),

-- En desarrollo limitamos datos para ahorrar coste
{% if var('is_dev', true) %}
filtered as (
    select * from appointments
    where date(appointment_start_at) >= date_sub(current_date(), interval 90 day)
),
{% else %}
filtered as (
    select * from appointments
),
{% endif %}

final as (
    select
        appointment_id,
        patient_id,
        doctor_id,
        specialty_id,
        country_id,
        date(appointment_start_at)              as appointment_date,
        appointment_created_at,
        appointment_start_at,
        updated_at,
        status,
        channel,
        cancellation_reason,
        is_first_appointment,
        source_lead_id,
        patient_age_at_appointment,
        doctor_rating,
        patient_appointment_sequence,
        days_since_last_appointment,
        amount_cents,
        {{ cents_to_euros('amount_cents') }}    as amount_eur,
        payment_status,
        is_missing_payment

    from filtered
)

select * from final
