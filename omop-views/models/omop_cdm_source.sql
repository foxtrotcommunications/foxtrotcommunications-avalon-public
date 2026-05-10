{{ config(materialized='table') }}

-- OMOP CDM 5.4 — CDM_SOURCE
-- Required metadata table describing this CDM instance.
-- Ref: https://ohdsi.github.io/CommonDataModel/cdm54.html#CDM_SOURCE

SELECT
  'Avalon OMOP (Forge-Synthea)' AS cdm_source_name,
  'Foxtrot Communications — Avalon OMOP views built from Synthea FHIR bundles '
    || 'ingested and normalized by Forge into BigQuery, then transformed via dbt.'
    AS cdm_source_abbreviation,
  'OMOP CDM 5.4' AS cdm_holder,
  'https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public'
    AS source_description,
  'https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public'
    AS source_documentation_reference,
  'OMOP CDM v5.4' AS cdm_etl_reference,
  CURRENT_DATE() AS source_release_date,
  CURRENT_DATE() AS cdm_release_date,
  'CDM v5.4' AS cdm_version,
  -- Vocabulary version: will be populated from the vocabulary tables if loaded.
  {% if var('vocab_loaded', false) %}
  (SELECT vocabulary_version
   FROM `{{ var('omop_vocab_project') }}.{{ var('omop_vocab_dataset') }}.vocabulary`
   WHERE vocabulary_id = 'None'
   LIMIT 1) AS vocabulary_version
  {% else %}
  CAST(NULL AS STRING) AS vocabulary_version
  {% endif %}
