-- INTERMEDIATE: int_lead_to_appointment_funnel
--
-- Funnel completo: lead -> cita -> pago. Una fila por lead.
-- Permite analizar tasas de conversión en cada paso del embudo.
--
-- DATE_DIFF(fecha1, fecha2, DAY): días entre dos fechas.
-- Usamos para medir velocidad de conversión: ¿cuánto tarda un lead
-- en convertirse en cita? ¿y en pago?

with leads as (
    select * from {{ ref('stg_leads') }}
),

appointments as (
    select
        appointment_id,
        appointment_created_at,
        appointment_start_at,
        status
    from {{ ref('stg_appointments') }}
),

payments as (
    select
        appointment_id,
        payment_created_at,
        amount_cents,
        payment_status
    from {{ ref('stg_payments') }}
),

funnel as (
    select
        l.lead_id,
        l.patient_id,
        l.specialty_id,
        l.country_id,
        l.lead_source,
        l.lead_status,
        l.created_at                                        as lead_created_at,

        -- Paso 1: ¿Convirtió en cita?
        a.appointment_id,
        a.appointment_created_at,
        a.status                                            as appointment_status,

        -- Paso 2: ¿Hubo pago?
        p.payment_created_at,
        p.amount_cents,
        p.payment_status,

        -- Flags de conversión
        case when a.appointment_id is not null
            then true else false end                        as is_converted_to_appointment,

        case when p.appointment_id is not null
            then true else false end                        as is_converted_to_payment,

        -- Velocidad de conversión en días (fecha real de la cita, no de registro)
        date_diff(
            date(a.appointment_start_at),
            date(l.created_at),
            day
        )                                                   as days_lead_to_appointment,

        date_diff(
            date(p.payment_created_at),
            date(a.appointment_created_at),
            day
        )                                                   as days_appointment_to_payment

    from leads l
    left join appointments a
        on l.converted_appointment_id = a.appointment_id
    left join payments p
        on a.appointment_id = p.appointment_id
        and p.payment_status = 'paid'
)

select * from funnel
