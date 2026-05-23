{{ config(materialized='table') }}

-- OMOP CDM 5.4 — OBSERVATION (non-numeric)

SELECT
  ABS(FARM_FINGERPRINT(CONCAT(patient_id, '|', encounter_id, '|', code))) AS observation_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  {{ resolve_concept('cm_obs', 0) }} AS observation_concept_id,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(effective_date, 1, 10)) AS observation_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(effective_date, 1, 19)) AS observation_datetime,
  38000280 AS observation_type_concept_id,
  CAST(NULL AS FLOAT64) AS value_as_number,
  value_string AS value_as_string,
  {{ resolve_concept('cm_obs_val', 0) }} AS value_as_concept_id,
  0 AS qualifier_concept_id,
  0 AS unit_concept_id,  -- unit not applicable for coded observations
  CAST(NULL AS INT64) AS provider_id,
  ABS(FARM_FINGERPRINT(encounter_id)) AS visit_occurrence_id,
  CAST(NULL AS INT64) AS visit_detail_id,
  code AS observation_source_value,
  {{ resolve_source_concept('sc_obs', 0) }} AS observation_source_concept_id,
  value_unit                    AS unit_source_value,
  value_codeable_concept_display AS value_source_value,
  CAST(NULL AS INT64) AS observation_event_id,
  0 AS obs_event_field_concept_id
FROM {{ ref('stg_observation') }} obs
{{ resolve_concept_join('cm_obs', 'obs.code', 'SNOMED') }}
{{ resolve_concept_join('cm_obs_val', 'obs.value_codeable_concept_code', 'SNOMED') }}
{{ resolve_source_join('sc_obs', 'obs.code', 'SNOMED') }}
WHERE value_quantity IS NULL
   OR SAFE_CAST(value_quantity AS FLOAT64) IS NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY patient_id, encounter_id, code
  ORDER BY effective_date DESC
) = 1
