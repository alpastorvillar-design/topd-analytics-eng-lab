-- STAGING: stg_payments
--
-- amount_cents: los pagos se almacenan en céntimos (entero) para evitar
-- problemas de precisión de floating point. 1500 = 15.00 EUR.
-- La conversión a euros se hace en marts con la macro cents_to_euros().
--
-- Los floats tienen errores de redondeo: 14.99 * 100 puede dar 1498.9999...
-- Guardar como INTEGER (céntimos) elimina ese problema en sistemas de pago.

with source as (
    select * from {{ source('mediconnect', 'payments') }}
),

renamed as (
    select
        payment_id,
        appointment_id,
        patient_id,
        doctor_id,
        cast(payment_created_at as timestamp)   as payment_created_at,
        cast(updated_at as timestamp)           as updated_at,
        cast(amount_cents as int64)             as amount_cents,
        upper(currency)                         as currency,
        lower(payment_status)                   as payment_status,
        lower(payment_method)                   as payment_method

    from source
)

select * from renamed
