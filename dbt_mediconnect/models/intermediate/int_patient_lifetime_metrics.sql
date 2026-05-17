-- INTERMEDIATE: int_patient_lifetime_metrics
--
-- MÃ©tricas de ciclo de vida por paciente. Una fila por paciente.
-- Estas mÃ©tricas alimentan dim_patients y mart_patient_retention.
--
-- COUNTIF(condiciÃ³n): BigQuery-specific. Equivale a COUNT(CASE WHEN ... END).
-- SAFE_DIVIDE(a, b): divide sin error si b = 0. Devuelve NULL en vez de crash.
-- DATE_TRUNC(fecha, MONTH): trunca fecha al primer dÃ­a del mes.
--   Ãštil para cohort analysis: todos los pacientes del mismo mes de registro
--   forman una cohorte.

with appointments as (
    select * from {{ ref('int_appointments_enriched') }}
),

patients as (
    select * from {{ ref('stg_patients') }}
),

patient_metrics as (
    select
        a.patient_id,

        -- Volumen
        count(*)                                            as total_appointments,
        countif(a.status = 'completed')                    as completed_appointments,
        countif(a.status = 'cancelled')                    as cancelled_appointments,
        countif(a.status = 'no_show')                      as no_show_appointments,

        -- Fechas
        min(date(a.appointment_start_at))                  as first_appointment_date,
        max(date(a.appointment_start_at))                  as last_appointment_date,
        date_diff(
            max(date(a.appointment_start_at)),
            min(date(a.appointment_start_at)),
            day
        )                                                   as days_as_patient,

        -- Revenue
        sum(case when a.payment_status = 'paid'
            then a.amount_cents else 0 end)                as total_revenue_cents,

        -- Ratios (SAFE_DIVIDE evita divisiÃ³n por cero)
        safe_divide(
            countif(a.status = 'no_show'),
            count(*)
        )                                                   as no_show_rate,

        safe_divide(
            countif(a.status = 'cancelled'),
            count(*)
        )                                                   as cancellation_rate,

        -- Especialidades distintas consultadas
        count(distinct a.specialty_id)                     as distinct_specialties_consulted

    from appointments a
    group by a.patient_id
),

final as (
    select
        p.patient_id,
        p.acquisition_channel,
        p.country_id,
        -- Mes de registro -> cohorte para retention analysis
        date_trunc(date(p.created_at), month)              as cohort_month,
        m.* EXCEPT (patient_id)

    from patients p
    left join patient_metrics m using (patient_id)
)

select * from final
