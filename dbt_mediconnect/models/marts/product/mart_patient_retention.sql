-- MART PRODUCT: mart_patient_retention
--
-- Análisis de retención por cohorte mensual.
-- Una fila por (cohort_month, months_since_acquisition).
--
-- ¿Qué es cohort analysis?
-- Agrupa usuarios por su mes de registro (cohorte) y mide
-- qué % siguen activos en los meses siguientes.
-- Es la métrica más importante para entender retención de producto.
--
-- Ejemplo de resultado:
-- cohort_month | month_number | cohort_size | retained_patients | retention_rate
-- 2022-01-01   | 0            | 150         | 150               | 1.00
-- 2022-01-01   | 1            | 150         | 87                | 0.58
-- 2022-01-01   | 2            | 150         | 61                | 0.41

with patients as (
    select
        patient_id,
        cohort_month
    from {{ ref('int_patient_lifetime_metrics') }}
    where cohort_month is not null
),

appointments as (
    select
        patient_id,
        date_trunc(appointment_date, month)     as activity_month
    from {{ ref('fct_appointments') }}
    where status = 'completed'
),

-- Cruzamos cada paciente con sus meses de actividad
patient_activity as (
    select
        p.patient_id,
        p.cohort_month,
        a.activity_month,
        date_diff(a.activity_month, p.cohort_month, month) as months_since_acquisition
    from patients p
    inner join appointments a using (patient_id)
),

-- Tamaño de cada cohorte
cohort_sizes as (
    select
        cohort_month,
        count(distinct patient_id)              as cohort_size
    from patients
    group by cohort_month
),

-- Pacientes retenidos por cohorte y mes
retention as (
    select
        cohort_month,
        months_since_acquisition,
        count(distinct patient_id)              as retained_patients
    from patient_activity
    group by cohort_month, months_since_acquisition
),

final as (
    select
        r.cohort_month,
        r.months_since_acquisition,
        cs.cohort_size,
        r.retained_patients,
        round(safe_divide(r.retained_patients, cs.cohort_size), 4) as retention_rate

    from retention r
    inner join cohort_sizes cs using (cohort_month)
)

select * from final
order by cohort_month, months_since_acquisition
