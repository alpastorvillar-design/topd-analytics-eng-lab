-- MACRO: classify_patient_segment
-- Segmenta pacientes según número de citas completadas.
-- Centralizar esta lógica evita inconsistencias entre modelos.

{% macro classify_patient_segment(completed_appointments) %}
    case
        when {{ completed_appointments }} = 0 then 'new'
        when {{ completed_appointments }} between 1 and 2 then 'active'
        when {{ completed_appointments }} between 3 and 6 then 'loyal'
        when {{ completed_appointments }} > 6 then 'champion'
        else 'unknown'
    end
{% endmacro %}
