-- Singular test: every lead with is_converted_to_appointment = true must have
-- a non-null appointment_id. A converted lead with no appointment_id indicates
-- a broken funnel record — the conversion flag is set but the reference is missing.

select lead_id
from {{ ref('fct_leads') }}
where
    is_converted_to_appointment = true
    and appointment_id is null
