-- MART CORE: dim_patients
--
-- DimensiÃ³n de pacientes. Una fila por paciente con atributos descriptivos
-- y mÃ©tricas de ciclo de vida pre-calculadas.
--
-- En un modelo dimensional (star schema):
-- - Las DIMENSIONES describen el QUIÃ‰N, QUÃ‰, DÃ“NDE, CUÃNDO
-- - Los HECHOS (facts) contienen las medidas numÃ©ricas y FK a dimensiones
--
-- dim_patients es el "QuiÃ©n" del anÃ¡lisis: describe al paciente.
-- fct_appointments usarÃ¡ patient_id como foreign key a esta dimensiÃ³n.

with patients as (
    select * from {{ ref('stg_patients') }}
),

metrics as (
    select * from {{ ref('int_patient_lifetime_metrics') }}
),

final as (
    select
        p.patient_id,
        p.full_name,
        p.gender,
        p.birth_date,
        date_diff(current_date(), p.birth_date, year)   as current_age,
        p.country_id,
        p.city,
        p.created_at,
        p.acquisition_channel,
        p.is_active,

        -- MÃ©tricas de ciclo de vida
        coalesce(m.total_appointments, 0)               as total_appointments,
        coalesce(m.completed_appointments, 0)           as completed_appointments,
        coalesce(m.total_revenue_cents, 0)              as total_revenue_cents,
        {{ cents_to_euros('coalesce(m.total_revenue_cents, 0)') }} as total_revenue_eur,
        m.first_appointment_date,
        m.last_appointment_date,
        m.cohort_month,
        m.no_show_rate,
        m.cancellation_rate,

        -- Segmento calculado con macro
        {{ classify_patient_segment('coalesce(m.completed_appointments, 0)') }} as patient_segment

    from patients p
    left join metrics m using (patient_id)
)

select * from final
