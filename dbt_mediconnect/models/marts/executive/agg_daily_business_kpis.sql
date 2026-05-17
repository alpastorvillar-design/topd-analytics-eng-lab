-- MART EXECUTIVE: agg_daily_business_kpis
-- KPIs diarios del negocio. Alimenta el dashboard ejecutivo.
-- SUM OVER para acumulados: permite ver tendencia sin perder detalle diario.

with appointments as (
    select
        appointment_date                            as date,
        count(*)                                    as total_appointments,
        countif(status = 'completed')               as completed_appointments,
        countif(status = 'no_show')                 as no_show_appointments,
        countif(status = 'cancelled')               as cancelled_appointments,
        countif(is_first_appointment = true)        as new_patient_appointments
    from {{ ref('fct_appointments') }}
    group by appointment_date
),

payments as (
    select
        payment_date                                as date,
        sum(case when payment_status = 'paid'
            then amount_eur else 0 end)             as daily_revenue_eur,
        countif(payment_status = 'paid')            as paid_payments,
        countif(payment_status = 'refunded')        as refunded_payments
    from {{ ref('fct_payments') }}
    group by payment_date
),

leads as (
    select
        lead_date                                   as date,
        count(*)                                    as total_leads,
        countif(is_converted_to_appointment = true) as converted_leads
    from {{ ref('fct_leads') }}
    group by lead_date
),

combined as (
    select
        coalesce(a.date, p.date, l.date)            as date,
        coalesce(a.total_appointments, 0)           as total_appointments,
        coalesce(a.completed_appointments, 0)       as completed_appointments,
        coalesce(a.no_show_appointments, 0)         as no_show_appointments,
        coalesce(a.new_patient_appointments, 0)     as new_patient_appointments,
        coalesce(p.daily_revenue_eur, 0)            as daily_revenue_eur,
        coalesce(p.paid_payments, 0)                as paid_payments,
        coalesce(l.total_leads, 0)                  as total_leads,
        coalesce(l.converted_leads, 0)              as converted_leads
    from appointments a
    full outer join payments p using (date)
    full outer join leads l using (date)
),

final as (
    select
        date,
        total_appointments,
        completed_appointments,
        no_show_appointments,
        new_patient_appointments,
        daily_revenue_eur,
        paid_payments,
        total_leads,
        converted_leads,

        -- Ratios diarios
        safe_divide(completed_appointments, total_appointments) as completion_rate,
        safe_divide(converted_leads, total_leads)               as lead_conversion_rate,

        -- Acumulados con window functions
        -- SUM OVER: suma desde el inicio hasta la fila actual
        sum(daily_revenue_eur) over (
            order by date
            rows between unbounded preceding and current row
        )                                                       as cumulative_revenue_eur,

        sum(total_appointments) over (
            order by date
            rows between unbounded preceding and current row
        )                                                       as cumulative_appointments

    from combined
)

select * from final
where total_appointments > 0
order by date
