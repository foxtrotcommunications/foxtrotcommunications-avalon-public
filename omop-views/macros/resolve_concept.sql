{% macro resolve_concept(source_code_col, vocabulary, fallback=0) %}
{#
  Resolve a FHIR source code to its OMOP Standard concept_id.

  Joins against omop_vocab.concept_map, which is the pre-computed view
  created by scripts/load_vocab.py:
    source_code + source_vocabulary → standard_concept_id

  Args:
    source_code_col : SQL expression for the source code column
                      (e.g., 'cond.code', 'obs.code')
    vocabulary      : Athena vocabulary_id string literal
                      ('SNOMED', 'LOINC', 'RxNorm', 'UCUM')
    fallback        : Value to use when no mapping exists (default: 0)

  Prerequisites:
    Run scripts/load_vocab.py first, then set vocab_loaded: true in
    dbt_project.yml vars (or pass --vars '{"vocab_loaded": true}').
    When vocab_loaded is false this macro returns the fallback value (0)
    directly, identical to the pre-vocabulary baseline.
#}
{% if var('vocab_loaded', false) %}
COALESCE(
  (
    SELECT cm.standard_concept_id
    FROM {{ source('omop_vocab', 'concept_map') }} cm
    WHERE cm.source_code       = CAST({{ source_code_col }} AS STRING)
      AND cm.source_vocabulary = '{{ vocabulary }}'
    LIMIT 1
  ),
  {{ fallback }}
)
{% else %}
{{ fallback }}
{% endif %}
{% endmacro %}


{% macro resolve_source_concept(source_code_col, vocabulary, fallback=0) %}
{#
  Resolve a FHIR source code to its OMOP *source* concept_id
  (the non-standard concept for the source vocabulary itself,
  before "Maps to" resolution). Used to populate *_source_concept_id fields.

  Args:
    source_code_col : SQL expression for the source code column
    vocabulary      : Athena vocabulary_id string literal
    fallback        : Value when no concept found (default: 0)
#}
{% if var('vocab_loaded', false) %}
COALESCE(
  (
    SELECT c.concept_id
    FROM {{ source('omop_vocab', 'concept') }} c
    WHERE c.concept_code  = CAST({{ source_code_col }} AS STRING)
      AND c.vocabulary_id = '{{ vocabulary }}'
      AND c.invalid_reason IS NULL
    LIMIT 1
  ),
  {{ fallback }}
)
{% else %}
{{ fallback }}
{% endif %}
{% endmacro %}
