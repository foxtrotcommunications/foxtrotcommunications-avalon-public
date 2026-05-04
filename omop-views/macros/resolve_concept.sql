{% macro resolve_concept(join_alias, fallback=0) %}
{#
  Reference a pre-joined concept resolution result.
  The join_alias must match a LEFT JOIN added via resolve_concept_join().
  
  Args:
    join_alias : The alias used in the LEFT JOIN (e.g., 'cm_snomed_code')
    fallback   : Value to use when no mapping exists (default: 0)
#}
{% if var('vocab_loaded', false) %}
COALESCE({{ join_alias }}.standard_concept_id, {{ fallback }})
{%- else %}
{{ fallback }}
{%- endif %}
{% endmacro %}


{% macro resolve_source_concept(join_alias, fallback=0) %}
{#
  Reference a pre-joined source concept resolution result.
  The join_alias must match a LEFT JOIN added via resolve_source_join().

  Args:
    join_alias : The alias used in the LEFT JOIN (e.g., 'sc_snomed_code')
    fallback   : Value when no concept found (default: 0)
#}
{% if var('vocab_loaded', false) %}
COALESCE({{ join_alias }}.concept_id, {{ fallback }})
{%- else %}
{{ fallback }}
{%- endif %}
{% endmacro %}


{% macro resolve_concept_join(join_alias, source_code_expr, vocabulary) %}
{#
  Emit a LEFT JOIN against the concept_map table for standard concept resolution.
  Add this in the FROM/JOIN section of your model.

  Args:
    join_alias       : Unique alias for this join (e.g., 'cm_snomed_code')
    source_code_expr : SQL expression for the source code column (e.g., 'cond.code')
    vocabulary       : Athena vocabulary_id ('SNOMED', 'LOINC', 'RxNorm', 'UCUM')
#}
{% if var('vocab_loaded', false) %}
LEFT JOIN {{ source('omop_vocab', 'concept_map') }} {{ join_alias }}
  ON {{ join_alias }}.source_code = CAST({{ source_code_expr }} AS STRING)
  AND {{ join_alias }}.source_vocabulary_id = '{{ vocabulary }}'
{%- endif %}
{% endmacro %}


{% macro resolve_source_join(join_alias, source_code_expr, vocabulary) %}
{#
  Emit a LEFT JOIN against the concept table for source concept resolution.
  Add this in the FROM/JOIN section of your model.

  Args:
    join_alias       : Unique alias for this join (e.g., 'sc_snomed_code')
    source_code_expr : SQL expression for the source code column
    vocabulary       : Athena vocabulary_id
#}
{% if var('vocab_loaded', false) %}
LEFT JOIN {{ source('omop_vocab', 'concept') }} {{ join_alias }}
  ON {{ join_alias }}.concept_code = CAST({{ source_code_expr }} AS STRING)
  AND {{ join_alias }}.vocabulary_id = '{{ vocabulary }}'
  AND {{ join_alias }}.invalid_reason IS NULL
{%- endif %}
{% endmacro %}
