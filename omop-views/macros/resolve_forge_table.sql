{% macro resolve_forge_table(source_name, semantic_key, resource_key) %}
{#
  Resolves a forge-core sub-table name using a 3-tier fallback:

  1. Config map (forge_table_map var) — fast, no warehouse call
  2. Compile-time discovery — queries INFORMATION_SCHEMA + table_path
  3. Default convention — root__root__raw_1__<4char><rank>

  Usage:
    {{ resolve_forge_table('forge_patient', 'extension', 'patient') }}
    → returns the actual table name string, e.g. "root__root__raw_1__exte1"

  Args:
    source_name: dbt source name (e.g. 'forge_patient')
    semantic_key: key in the forge_table_map (e.g. 'extension', 'code_coding')
    resource_key: resource type key (e.g. 'patient', 'encounter')
#}

{# ── Tier 1: Check config map ────────────────────────────────── #}
{% set forge_tables = var('forge_tables', {}) %}
{% if resource_key in forge_tables and semantic_key in forge_tables[resource_key] %}
  {% set resolved = forge_tables[resource_key][semantic_key] %}
  {{ return(resolved) }}
{% endif %}

{# ── Tier 2: Compile-time discovery via table_path ───────────── #}
{# Only runs if config map didn't have the answer.
   Queries the dataset's INFORMATION_SCHEMA to find tables with
   table_path column, then checks which table has the matching path. #}
{% if execute %}
  {% set fhir_path_map = {
    'raw':           'root__root',
    'extension':     'root__root__extension',
    'ext_ext':       'root__root__extension__extension',
    'ext_ext_val':   'root__root__extension__extension__valueCoding',
    'class':         'root__root__class',
    'period':        'root__root__period',
    'participant':   'root__root__participant',
    'part_indiv':    'root__root__participant__individual',
    'subject':       'root__root__subject',
    'encounter':     'root__root__encounter',
    'code':          'root__root__code',
    'code_coding':   'root__root__code__coding',
    'performed':     'root__root__performedPeriod',
    'value':         'root__root__valueQuantity',
    'med_concept':   'root__root__medicationCodeableConcept',
    'med_coding':    'root__root__medicationCodeableConcept__coding',
  } %}

  {% set target_path = fhir_path_map.get(semantic_key) %}
  {% if target_path %}
    {% set dataset_var = source_name | replace('forge_', 'forge_') ~ '_dataset' %}
    {% set ds = var(dataset_var, '') %}
    {% set proj = var('forge_project', '') %}

    {% if ds and proj %}
      {# Find all root__ tables in the dataset #}
      {% set info_query %}
        SELECT DISTINCT table_name
        FROM `{{ proj }}.{{ ds }}.INFORMATION_SCHEMA.TABLES`
        WHERE table_name LIKE 'frg\_\_%'
      {% endset %}

      {% set tables_result = run_query(info_query) %}
      {% if tables_result %}
        {% for row in tables_result %}
          {% set tbl = row['table_name'] %}
          {# Check if this table has the target table_path #}
          {% set path_query %}
            SELECT table_path
            FROM `{{ proj }}.{{ ds }}.{{ tbl }}`
            WHERE table_path IS NOT NULL
            LIMIT 1
          {% endset %}
          {% set path_result = run_query(path_query) %}
          {% if path_result and path_result[0]['table_path'] == target_path %}
            {{ return(tbl) }}
          {% endif %}
        {% endfor %}
      {% endif %}
    {% endif %}
  {% endif %}
{% endif %}

{# ── Tier 3: Return None — caller should handle ─────────────── #}
{{ return(none) }}
{% endmacro %}
