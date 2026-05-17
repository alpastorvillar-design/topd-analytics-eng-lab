-- MART CORE: fct_appointments
--
-- Tabla de hechos de citas. Una fila por cita.
--
-- Materialization: incremental con estrategia 'merge'.
--   - Primer run: materializa la tabla entera.
--   - Runs siguientes: solo procesa filas con updated_at posterior al mÃ¡ximo
--     ya cargado, y hace upsert por appointment_id (las citas pueden cambiar
--     de status: scheduled -> completed -> cancelled).
--   - Para forzar reproceso completo: dbt run --select fct_appointments --full-refresh
--
-- Partition: appointment_date (MONTH) para reducir bytes escaneados.
-- Cluster: country_id, specialty_id, status para acelerar filtros en dashboards.

{{
    config(
        materialized='incremental',
        unique_key='appointment_id',
        incremental_strategy='merge',
        partition_by={
            'field': 'appointment_date',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['country_id', 'specialty_id', 'status'],
        on_schema_change='append_new_columns'
    )
}}

with appointments as (
    select * from {{ ref('int_appointments_enriched') }}
),

{% if var('is_dev', false) %}
date_anchor as (
    select date_sub(max(date(appointment_start_at)),
                    interval {{ var('dev_window_days', 90) }} day) as min_date
    from appointments
),
filtered as (
    select a.* from appointments a
    cross join date_anchor d
    where date(a.appointment_start_at) >= d.min_date
),
{% else %}
filtered as (
    select * from appointments
),
{% endif %}

{% if is_incremental() %}
-- Solo procesa filas modificadas desde el Ãºltimo run.
-- {{ this }} se resuelve a la tabla destino actual.
incremental_filter as (
    select * from filtered
    where updated_at > (select coalesce(max(updated_at), timestamp('1970-01-01'))
                        from {{ this }})
),
{% else %}
incremental_filter as (
    select * from filtered
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

    from incremental_filter
)

select * from final
