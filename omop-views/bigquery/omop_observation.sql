-- ─────────────────────────────────────────────────────────────────
-- omop_observation — OMOP CDM 5.4
--
-- Source:  FHIR Observation (non-numeric) → forge-core `observation` table
-- Target:  OMOP OBSERVATION
--
-- Captures observations where value_quantity is NULL or not parseable
-- as a number (categorical findings, assessments, surveys).
--
-- Placeholders: {project}, {dataset}
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW `{project}.{dataset}.omop_observation` AS

SELECT
  ABS(FARM_FINGERPRINT(resource_id)) AS observation_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  0 AS observation_concept_id,  -- requires vocabulary JOIN for LOINC → OMOP mapping
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(effective_date, 1, 10)) AS observation_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(effective_date, 1, 19)) AS observation_datetime,
  38000280 AS observation_type_concept_id,  -- Observation recorded from EHR
  CAST(NULL AS FLOAT64) AS value_as_number,
  CAST(NULL AS STRING) AS value_as_string,
  0 AS value_as_concept_id,
  0 AS qualifier_concept_id,
  0 AS unit_concept_id,
  CAST(NULL AS INT64) AS provider_id,
  ABS(FARM_FINGERPRINT(encounter_id)) AS visit_occurrence_id,
  CAST(NULL AS INT64) AS visit_detail_id,
  code AS observation_source_value,
  0 AS observation_source_concept_id,
  value_unit AS unit_source_value,
  value_quantity AS value_source_value,
  CAST(NULL AS INT64) AS observation_event_id,
  0 AS obs_event_field_concept_id
FROM `{project}.{dataset}.observation`
WHERE value_quantity IS NULL
   OR SAFE_CAST(value_quantity AS FLOAT64) IS NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY patient_id, encounter_id, code
  ORDER BY effective_date DESC
) = 1;
