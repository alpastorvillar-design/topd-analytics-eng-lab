-- MACRO: safe_divide
-- Devuelve NULL si el denominador es 0 o NULL.
-- Wrapper portable: BigQuery tiene SAFE_DIVIDE nativa, pero esto funciona
-- igual en otros warehouses si el proyecto migra.

{% macro safe_divide(numerator, denominator) %}
    case
        when {{ denominator }} = 0 or {{ denominator }} is null
        then null
        else {{ numerator }} / {{ denominator }}
    end
{% endmacro %}
