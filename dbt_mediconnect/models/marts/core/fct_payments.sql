-- MART CORE: fct_payments
-- Tabla de hechos de pagos. Una fila por pago.
-- Particionada por mes para consultas de revenue eficientes.

{{
    config(
        materialized='table',
        partition_by={
            'field': 'payment_date',
            'data_type': 'date',
            'granularity': 'month'
        },
        cluster_by=['country_id', 'payment_status', 'payment_method']
    )
}}

with payments as (
    select * from {{ ref('stg_payments') }}
),

appointments as (
    select
        appointment_id,
        specialty_id,
        country_id,
        channel
    from {{ ref('stg_appointments') }}
),

final as (
    select
        p.payment_id,
        p.appointment_id,
        p.patient_id,
        p.doctor_id,
        a.specialty_id,
        a.country_id,
        date(p.payment_created_at)              as payment_date,
        p.payment_created_at,
        p.updated_at,
        p.amount_cents,
        {{ cents_to_euros('p.amount_cents') }}  as amount_eur,
        p.currency,
        p.payment_status,
        p.payment_method

    from payments p
    left join appointments a using (appointment_id)
)

select * from final
