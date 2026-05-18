-- INTERMEDIATE: int_appointments_enriched
-- Join entre appointments, doctors, patients y payments.
-- Añade métricas de secuencia por paciente vía window functions:
-- ROW_NUMBER para número de visita, LAG para días entre citas.

with appointments as (
    select * from {{ ref('stg_appointments') }}
),

doctors as (
    select doctor_id, specialty_id, country_id, rating
    from {{ ref('stg_doctors') }}
),

patients as (
    select patient_id, country_id as patient_country_id, birth_date
    from {{ ref('stg_patients') }}
),

payments as (
    select appointment_id, amount_cents, payment_status
    from {{ ref('stg_payments') }}
),

enriched as (
    select
        a.appointment_id,
        a.patient_id,
        a.doctor_id,
        a.appointment_created_at,
        a.appointment_start_at,
        a.updated_at,
        a.status,
        a.channel,
        a.cancellation_reason,
        a.is_first_appointment,
        a.source_lead_id,

        -- Contexto del médico
        d.specialty_id,
        d.country_id,
        d.rating as doctor_rating,

        -- Contexto del paciente
        date_diff(
            date(a.appointment_start_at),
            p.birth_date,
            year
        )                                           as patient_age_at_appointment,

        -- Contexto del pago
        pay.amount_cents,
        pay.payment_status,

        -- Flags calculados
        case
            when a.status = 'completed' and pay.appointment_id is null then true
            else false
        end                                         as is_missing_payment,

        -- Window: número de cita del paciente en orden cronológico
        -- QUALIFY es BigQuery-specific: filtra sobre window functions sin subquery
        row_number() over (
            partition by a.patient_id
            order by a.appointment_start_at asc
        )                                           as patient_appointment_sequence,

        -- Window: días desde la cita anterior del mismo paciente
        date_diff(
            date(a.appointment_start_at),
            date(lag(a.appointment_start_at) over (
                partition by a.patient_id
                order by a.appointment_start_at asc
            )),
            day
        )                                           as days_since_last_appointment

    from appointments a
    left join doctors d using (doctor_id)
    left join patients p using (patient_id)
    left join payments pay using (appointment_id)
)

select * from enriched
