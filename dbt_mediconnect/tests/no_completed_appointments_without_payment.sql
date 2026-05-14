-- TEST SINGULAR: no_completed_appointments_without_payment
--
-- ¿Qué es un test singular en dbt?
-- Un archivo SQL que devuelve las filas que FALLAN el test.
-- Si la query devuelve 0 filas → test pasa. Si devuelve filas → test falla.
--
-- Regla de negocio: toda cita con status='completed' debe tener un pago
-- con payment_status IN ('paid', 'refunded').
-- Un completed sin pago es un error de datos o de proceso.

select
    appointment_id,
    status,
    payment_status
from {{ ref('fct_appointments') }}
where
    status = 'completed'
    and (payment_status is null or payment_status not in ('paid', 'refunded'))
