-- MACRO: round_rate
-- Rounds a rate or ratio to 4 decimal places.
-- Companion to safe_divide: apply when storing rates in marts or intermediates.
-- Example: {{ round_rate('safe_divide(completed, total)') }}

{% macro round_rate(expr) %}
    round({{ expr }}, 4)
{% endmacro %}
