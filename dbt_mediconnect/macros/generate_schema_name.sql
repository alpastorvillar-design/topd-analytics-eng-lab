-- Sobrescribe el comportamiento por defecto de dbt que concatena
-- target_schema + custom_schema (ej: dbt_staging_dbt_marts).
-- Con este macro, los modelos van directamente al schema especificado
-- en dbt_project.yml sin prefijo adicional.

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
