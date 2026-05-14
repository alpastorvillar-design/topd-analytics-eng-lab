-- MACRO: generate_surrogate_key
-- MD5 hash de los campos concatenados con separador '|'.
-- Alternativa explícita a dbt_utils.generate_surrogate_key para
-- mantener control sobre el formato del hash en este proyecto.

{% macro generate_surrogate_key(field_list) %}
    to_hex(md5(concat(
        {% for field in field_list %}
            coalesce(cast({{ field }} as string), 'NULL')
            {% if not loop.last %} || '|' || {% endif %}
        {% endfor %}
    )))
{% endmacro %}
