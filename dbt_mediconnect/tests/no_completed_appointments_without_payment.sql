-- TEST SINGULAR: no_completed_appointments_without_payment
--
-- Regla de negocio: toda cita con status='completed' debe tener un pago
-- con payment_status IN ('paid', 'refunded').
-- Marcado como warn porque los datos sinteticos no garantizan cobertura
-- total de pagos para citas completadas.
{{ config(severity='warn') }}

select
    appointment_id,
    status,
    payment_status
from {{ ref('fct_appointments') }}
where
    status = 'completed'
    and (payment_status is null or payment_status not in ('paid', 'refunded'))
