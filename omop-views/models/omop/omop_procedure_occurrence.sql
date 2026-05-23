{{ config(materialized='table') }}

-- OMOP CDM 5.4 — PROCEDURE_OCCURRENCE

SELECT
  ABS(FARM_FINGERPRINT(CONCAT(proc.patient_id, '|', proc.encounter_id, '|', proc.code))) AS procedure_occurrence_id,
  ABS(FARM_FINGERPRINT(proc.patient_id)) AS person_id,
  {{ resolve_concept('cm_proc', 0) }} AS procedure_concept_id,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(proc.performed_start, 1, 10)) AS procedure_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(proc.performed_start, 1, 19)) AS procedure_datetime,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(proc.performed_end, 1, 10)) AS procedure_end_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(proc.performed_end, 1, 19)) AS procedure_end_datetime,
  38000275 AS procedure_type_concept_id,
  0 AS modifier_concept_id,
  CAST(NULL AS INT64) AS quantity,
  COALESCE(ABS(FARM_FINGERPRINT(enc.participant_individual_reference)), 0) AS provider_id,
  ABS(FARM_FINGERPRINT(proc.encounter_id)) AS visit_occurrence_id,
  CAST(NULL AS INT64) AS visit_detail_id,
  proc.code AS procedure_source_value,
  {{ resolve_source_concept('sc_proc', 0) }} AS procedure_source_concept_id,
  CAST(NULL AS STRING) AS modifier_source_value
FROM {{ ref('stg_procedure') }} proc
LEFT JOIN (
  SELECT resource_id, participant_individual_reference
  FROM {{ ref('stg_encounter') }}
  QUALIFY ROW_NUMBER() OVER (PARTITION BY resource_id ORDER BY ingestion_timestamp DESC) = 1
) enc
  ON enc.resource_id = proc.encounter_id
{{ resolve_concept_join('cm_proc', 'proc.code', 'SNOMED') }}
{{ resolve_source_join('sc_proc', 'proc.code', 'SNOMED') }}
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY proc.patient_id, proc.encounter_id, proc.code
  ORDER BY proc.performed_start DESC
) = 1
