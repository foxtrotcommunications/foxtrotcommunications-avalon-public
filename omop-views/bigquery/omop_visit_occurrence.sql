-- ─────────────────────────────────────────────────────────────────
-- omop_visit_occurrence — OMOP CDM 5.4
--
-- Source:  FHIR Encounter → forge-core `encounter` table
-- Target:  OMOP VISIT_OCCURRENCE
--
-- Visit concept mapping:
--   AMB  → 9202  (Outpatient)
--   IMP  → 9201  (Inpatient)
--   EMER → 9203  (Emergency)
--   VR   → 581399 (Telehealth)
--   HH   → 581476 (Home Health)
--
-- Placeholders: {project}, {dataset}
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW `{project}.{dataset}.omop_visit_occurrence` AS

SELECT
  ABS(FARM_FINGERPRINT(resource_id)) AS visit_occurrence_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  CASE class_code
    WHEN 'AMB' THEN 9202
    WHEN 'IMP' THEN 9201
    WHEN 'EMER' THEN 9203
    WHEN 'VR' THEN 581399
    WHEN 'HH' THEN 581476
    ELSE 0
  END AS visit_concept_id,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(period_start, 1, 10)) AS visit_start_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(period_start, 1, 19)) AS visit_start_datetime,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(period_end, 1, 10)) AS visit_end_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(period_end, 1, 19)) AS visit_end_datetime,
  44818518 AS visit_type_concept_id,  -- EHR
  COALESCE(ABS(FARM_FINGERPRINT(participant_individual_reference)), 0) AS provider_id,
  CAST(NULL AS INT64) AS care_site_id,
  resource_id AS visit_source_value,
  class_code AS visit_source_concept_id,
  0 AS admitted_from_concept_id,
  CAST(NULL AS STRING) AS admitted_from_source_value,
  0 AS discharged_to_concept_id,
  CAST(NULL AS STRING) AS discharged_to_source_value,
  CAST(NULL AS INT64) AS preceding_visit_occurrence_id
FROM `{project}.{dataset}.encounter`
QUALIFY ROW_NUMBER() OVER (PARTITION BY resource_id ORDER BY ingestion_timestamp DESC) = 1;
