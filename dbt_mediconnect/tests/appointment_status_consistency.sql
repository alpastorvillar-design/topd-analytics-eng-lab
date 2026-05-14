-- TEST SINGULAR: appointment_status_consistency
-- Regla: si lead_status = 'converted', debe existir un appointment_id válido.
-- Un lead convertido sin cita asociada es inconsistencia referencial.

select
    lead_id,
    lead_status,
    appointment_id
from {{ ref('fct_leads') }}
where
    lead_status = 'converted'
    and appointment_id is null
