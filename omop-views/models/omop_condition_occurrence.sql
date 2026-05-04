{{ config(materialized='table') }}

-- OMOP CDM 5.4 — CONDITION_OCCURRENCE
-- Maps forge-core Condition → OMOP condition_occurrence
-- Excludes social determinant findings, deduplicates per patient+encounter+code

SELECT
  ABS(FARM_FINGERPRINT(CONCAT(cond.patient_id, '|', cond.encounter_id, '|', cond.code))) AS condition_occurrence_id,
  ABS(FARM_FINGERPRINT(cond.patient_id)) AS person_id,
  {{ resolve_concept('cm_cond', 0) }} AS condition_concept_id,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(cond.effective_date, 1, 10)) AS condition_start_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(cond.effective_date, 1, 19)) AS condition_start_datetime,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(cond.abatement_date_time, 1, 10)) AS condition_end_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(cond.abatement_date_time, 1, 19)) AS condition_end_datetime,
  32020 AS condition_type_concept_id,
  CAST(NULL AS STRING) AS stop_reason,
  COALESCE(ABS(FARM_FINGERPRINT(enc.participant_individual_reference)), 0) AS provider_id,
  ABS(FARM_FINGERPRINT(cond.encounter_id)) AS visit_occurrence_id,
  CAST(NULL AS INT64) AS visit_detail_id,
  cond.code AS condition_source_value,
  {{ resolve_source_concept('sc_cond', 0) }} AS condition_source_concept_id,
  REGEXP_EXTRACT(cond.clinical_status, r'"code":"([^"]+)"') AS condition_status_source_value,
  CASE REGEXP_EXTRACT(cond.clinical_status, r'"code":"([^"]+)"')
    WHEN 'active'   THEN 32901
    WHEN 'resolved' THEN 32906
    WHEN 'inactive' THEN 32907
    ELSE 0
  END AS condition_status_concept_id
FROM {{ ref('stg_condition') }} cond
LEFT JOIN (
  SELECT resource_id, participant_individual_reference
  FROM {{ ref('stg_encounter') }}
  QUALIFY ROW_NUMBER() OVER (PARTITION BY resource_id ORDER BY ingestion_timestamp DESC) = 1
) enc
  ON enc.resource_id = cond.encounter_id
{{ resolve_concept_join('cm_cond', 'cond.code', 'SNOMED') }}
{{ resolve_source_join('sc_cond', 'cond.code', 'SNOMED') }}
WHERE cond.code_display NOT IN (
  SELECT code_display FROM {{ ref('condition_exclusions') }}
)
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY cond.patient_id, cond.encounter_id, cond.code
  ORDER BY cond.effective_date DESC
) = 1
