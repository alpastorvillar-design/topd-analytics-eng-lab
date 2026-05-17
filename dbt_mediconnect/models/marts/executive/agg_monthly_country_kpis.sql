-- MART EXECUTIVE: agg_monthly_country_kpis
-- KPIs mensuales por paÃ­s. Para comparaciÃ³n geogrÃ¡fica en dashboards.

with appointments as (
    select
        date_trunc(appointment_date, month)     as month,
        country_id,
        count(*)                                as total_appointments,
        countif(status = 'completed')           as completed_appointments,
        countif(status = 'no_show')             as no_show_appointments,
        count(distinct patient_id)              as unique_patients,
        count(distinct doctor_id)               as active_doctors
    from {{ ref('fct_appointments') }}
    group by month, country_id
),

revenue as (
    select
        date_trunc(payment_date, month)         as month,
        country_id,
        sum(amount_eur)                         as total_revenue_eur
    from {{ ref('fct_payments') }}
    where payment_status = 'paid'
    group by month, country_id
),

countries as (
    select country_id, country_name, region
    from {{ ref('dim_countries') }}
),

final as (
    select
        a.month,
        a.country_id,
        c.country_name,
        c.region,
        a.total_appointments,
        a.completed_appointments,
        a.no_show_appointments,
        a.unique_patients,
        a.active_doctors,
        coalesce(r.total_revenue_eur, 0)        as total_revenue_eur,

        safe_divide(
            a.completed_appointments,
            a.total_appointments
        )                                       as completion_rate,

        safe_divide(
            coalesce(r.total_revenue_eur, 0),
            a.unique_patients
        )                                       as revenue_per_patient,

        -- Ranking de paÃ­ses por revenue ese mes
        rank() over (
            partition by a.month
            order by coalesce(r.total_revenue_eur, 0) desc
        )                                       as country_revenue_rank

    from appointments a
    left join revenue r using (month, country_id)
    left join countries c using (country_id)
)

select * from final
