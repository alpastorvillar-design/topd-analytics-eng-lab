-- MART CORE: fct_leads
-- Tabla de hechos de leads con datos del funnel de conversiÃ³n.

{{
    config(
        materialized='table',
        cluster_by=['country_id', 'lead_source', 'lead_status']
    )
}}

with funnel as (
    select * from {{ ref('int_lead_to_appointment_funnel') }}
)

select
    lead_id,
    patient_id,
    specialty_id,
    country_id,
    date(lead_created_at)                   as lead_date,
    lead_created_at,
    lead_source,
    lead_status,
    appointment_id,
    appointment_status,
    is_converted_to_appointment,
    is_converted_to_payment,
    amount_cents,
    {{ cents_to_euros('amount_cents') }}    as amount_eur,
    payment_status,
    days_lead_to_appointment,
    days_appointment_to_payment

from funnel
