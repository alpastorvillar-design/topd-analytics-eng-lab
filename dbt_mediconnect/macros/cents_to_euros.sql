-- MACRO: cents_to_euros
-- Convierte céntimos (INTEGER) a euros (FLOAT) con 2 decimales.
-- Usar en marts cuando se presentan valores monetarios al negocio.

{% macro cents_to_euros(amount_cents) %}
    round({{ amount_cents }} / 100.0, 2)
{% endmacro %}
