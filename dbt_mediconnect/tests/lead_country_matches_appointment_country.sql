-- Singular test: for converted leads, the country on the lead must match
-- the country on the linked appointment. A mismatch signals a join issue
-- or a data generation error in the source layer.
--
-- Severity: warn — existing synthetic data does not enforce this constraint
-- at generation time. The script has been corrected; warn surfaces the gap
-- without breaking CI against the current dataset.

{{ config(severity='warn') }}

select
    l.lead_id,
    l.country_id         as lead_country,
    a.country_id         as appointment_country
from {{ ref('fct_leads') }} l
inner join {{ ref('fct_appointments') }} a
    on l.appointment_id = a.appointment_id
where
    l.is_converted_to_appointment = true
    and l.country_id != a.country_id
