-- 04_bigquery_specific.sql: BigQuery vs PostgreSQL
-- COUNTIF, SAFE_DIVIDE, QUALIFY, DATE_TRUNC/DIFF, GENERATE_DATE_ARRAY,
-- UNNEST, partition pruning, IF, FORMAT_DATE. Equivalentes PG incluidos.


-- 1. COUNTIF (BigQuery) vs COUNT FILTER (PostgreSQL)
select
    DATE_TRUNC(appointment_date, month)         as month,
    COUNTIF(status = 'completed')               as completed,
    COUNTIF(status = 'no_show')                 as no_show,
    COUNTIF(is_first_appointment = TRUE)        as new_patients
from `topd-lab.dbt_marts.fct_appointments`
group by month;

-- PostgreSQL equivalente:
-- COUNT(*) FILTER (WHERE status = 'completed')
-- O también: COUNT(CASE WHEN status = 'completed' THEN 1 END)


-- 2. SAFE_DIVIDE (BigQuery) vs / NULLIF (PostgreSQL)
-- BigQuery devuelve NULL si el denominador es 0, sin error.
select
    specialty_id,
    COUNT(*)                                    as total_appointments,
    COUNTIF(status = 'completed')               as completed,
    SAFE_DIVIDE(
        COUNTIF(status = 'completed'), COUNT(*)
    )                                           as completion_rate
from `topd-lab.dbt_marts.fct_appointments`
group by specialty_id;

-- PostgreSQL: completed::numeric / NULLIF(total, 0)


-- 3. QUALIFY: filtrar por window function sin subquery
-- El médico top por revenue en cada especialidad:
with doctor_rev as (
    select
        d.doctor_id,
        d.specialty_id,
        SUM(p.amount_eur) as revenue_eur
    from `topd-lab.dbt_marts.fct_payments`  as p
    join `topd-lab.dbt_marts.dim_doctors`   as d using (doctor_id)
    where p.payment_status = 'paid'
    group by d.doctor_id, d.specialty_id
)
select specialty_id, doctor_id, revenue_eur
from doctor_rev
qualify RANK() over (partition by specialty_id order by revenue_eur desc) = 1;

-- PostgreSQL necesita una subquery o CTE extra:
-- SELECT * FROM (SELECT ..., RANK() OVER (...) AS rnk FROM doctor_rev) WHERE rnk = 1


-- 4. DATE_TRUNC y DATE_DIFF
select
    appointment_id,
    appointment_date,
    DATE_TRUNC(appointment_date, month)     as month,
    DATE_TRUNC(appointment_date, year)      as year,
    DATE_DIFF(CURRENT_DATE(), appointment_date, day)    as days_ago,
    DATE_DIFF(CURRENT_DATE(), appointment_date, month)  as months_ago
from `topd-lab.dbt_marts.fct_appointments`
limit 10;

-- PostgreSQL:
-- DATE_TRUNC('month', appointment_date)  -- mismo nombre, parámetro como string
-- (CURRENT_DATE - appointment_date)      -- devuelve interval, no integer


-- 5. GENERATE_DATE_ARRAY y UNNEST
select date
from UNNEST(
    GENERATE_DATE_ARRAY('2023-01-01', '2023-12-31', interval 1 month)
) as date;

-- UNNEST también expande arrays a filas:
select name, tag
from `topd-lab.dbt_marts.dim_doctors`
cross join UNNEST(tags) as tag   -- si tags fuera un campo ARRAY<STRING>
where tags is not NULL;


-- 6. Particionamiento y clustering: cómo afectan a los queries
-- fct_appointments está particionada por appointment_date (MONTH)
-- y tiene clustering en [country_id, specialty_id, status].

-- Esta query solo escanea las particiones de 2024 (partition pruning + clustering):
select COUNT(*), SUM(amount_eur)
from `topd-lab.dbt_marts.fct_payments`
where payment_date >= '2024-01-01'
  and country_id = 'ES'
  and payment_status = 'paid';


-- 7. IF y CASE: expresiones condicionales
-- IF(condición, valor_si_true, valor_si_false). Solo BigQuery.
select
    appointment_id,
    status,
    IF(status = 'completed', 'Exitosa', 'No completada')    as outcome,
    case status
        when 'completed' then 'Exitosa'
        when 'cancelled' then 'Cancelada'
        when 'no_show'   then 'No se presentó'
        else 'Pendiente'
    end                                                     as outcome_label,
    -- Pivot manual con IF:
    IF(status = 'completed', amount_eur, 0)                 as revenue_if_completed
from `topd-lab.dbt_marts.fct_appointments`
left join `topd-lab.dbt_marts.fct_payments` using (appointment_id)
limit 20;


-- 8. FORMAT_DATE y PARSE_DATE
select
    appointment_date,
    FORMAT_DATE('%Y-%m', appointment_date)      as year_month_str,
    FORMAT_DATE('%B %Y', appointment_date)      as month_name,
    FORMAT_DATE('%Q', appointment_date)         as quarter_number,
    CONCAT('Q', FORMAT_DATE('%Q', appointment_date),
           '-', FORMAT_DATE('%Y', appointment_date)) as quarter_label
from `topd-lab.dbt_marts.fct_appointments`
limit 5;
