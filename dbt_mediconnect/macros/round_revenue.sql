-- MACRO: round_revenue
-- Rounds a monetary EUR amount to 2 decimal places.
-- Use on SUM(amount_eur) aggregations to prevent floating-point artifacts.
-- Example: {{ round_revenue('sum(amount_eur)') }}

{% macro round_revenue(expr) %}
    round({{ expr }}, 2)
{% endmacro %}
