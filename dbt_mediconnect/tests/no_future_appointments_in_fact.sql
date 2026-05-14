-- TEST SINGULAR: no_future_appointments_in_fact
-- Las citas completadas o no_show no pueden tener fecha futura.
-- Solo 'scheduled' puede estar en el futuro.

select
    appointment_id,
    appointment_date,
    status
from {{ ref('fct_appointments') }}
where
    status in ('completed', 'no_show', 'cancelled')
    and appointment_date > current_date()
