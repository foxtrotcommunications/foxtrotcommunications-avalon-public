{% macro forge_join(child_alias, source_name, source_table, parent_alias, parent_depth) %}
{#
  LEFT JOIN a forge-core child sub-table to its parent using positional
  idx segment matching.

  Forge idx convention:
    frg__root         → 2 segments (depth 2)   e.g. "1_1"
    frg__root__raw_1  → 3 segments (depth 3)   e.g. "1_1_1"
    __raw_1__code1    → 4 segments (depth 4)   e.g. "1_1_1_1"

  Join: match first N segments positionally where N = parent's depth.

  Args:
    child_alias:   SQL alias for the child table
    source_name:   dbt source name (e.g. 'forge_patient')
    source_table:  semantic source table name (e.g. 'patient_extension')
    parent_alias:  SQL alias for the parent table
    parent_depth:  number of __ segments in parent's actual table name
                   frg__root = 2, frg__root__raw_1 = 3, etc.
#}
LEFT JOIN {{ source(source_name, source_table) }} {{ child_alias }}
  ON {{ child_alias }}.ingestion_hash = {{ parent_alias }}.ingestion_hash
  {% for i in range(parent_depth) %}
  AND SPLIT({{ child_alias }}.idx, '_')[SAFE_OFFSET({{ i }})] = SPLIT({{ parent_alias }}.idx, '_')[SAFE_OFFSET({{ i }})]
  {% endfor %}
{% endmacro %}
