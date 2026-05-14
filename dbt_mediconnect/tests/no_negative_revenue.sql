-- TEST SINGULAR: no_negative_revenue
-- Los pagos nunca deben tener amount_cents negativo.
-- Un valor negativo indicaría un error en la generación de datos o en el ETL.

select
    payment_id,
    amount_cents
from {{ ref('fct_payments') }}
where amount_cents < 0
