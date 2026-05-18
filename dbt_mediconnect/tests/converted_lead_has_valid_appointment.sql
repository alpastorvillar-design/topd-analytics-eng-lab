-- Singular test: every lead marked as converted must have a valid appointment_id
-- that exists in fct_appointments. A converted lead with no matching appointment
-- indicates a broken funnel linkage.

select
    l.lead_id,
    l.appointment_id
from {{ ref('fct_leads') }} l
where
    l.is_converted_to_appointment = true
    and l.appointment_id is not null
    and l.appointment_id not in (
        select appointment_id from {{ ref('fct_appointments') }}
    )
