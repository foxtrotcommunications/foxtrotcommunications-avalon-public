{% macro forge_join(child_alias, child_source, child_table, parent_alias, parent_table) %}
{#
  Generates a LEFT JOIN between forge-core sub-tables using positional idx segment matching.

  Forge idx convention: each nesting level adds one underscore-delimited segment.
    frg__root           → idx has N segments   (e.g. 1_1)
    frg__root__raw_1    → N+1 segments          (e.g. 1_1_1)
    __raw_1__name1      → N+2 segments          (e.g. 1_1_1_1)

  To join child → parent: match first N segments positionally,
  where N = parent's depth (number of __ parts in the table name).
#}
{% set parent_depth = parent_table.split('__') | length %}
LEFT JOIN {{ source(child_source, child_table) }} {{ child_alias }}
  ON {{ child_alias }}.ingestion_hash = {{ parent_alias }}.ingestion_hash
  {% for i in range(parent_depth) %}
  AND SPLIT({{ child_alias }}.idx, '_')[SAFE_OFFSET({{ i }})] = SPLIT({{ parent_alias }}.idx, '_')[SAFE_OFFSET({{ i }})]
  {% endfor %}
{% endmacro %}
