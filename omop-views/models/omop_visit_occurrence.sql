{{ config(materialized='table') }}

-- OMOP CDM 5.4 — VISIT_OCCURRENCE
-- Maps forge-core Encounter → OMOP visit_occurrence

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
  44818518 AS visit_type_concept_id,
  COALESCE(ABS(FARM_FINGERPRINT(participant_individual_reference)), 0) AS provider_id,
  COALESCE(ABS(FARM_FINGERPRINT(service_provider_reference)), 0) AS care_site_id,
  resource_id AS visit_source_value,
  class_code AS visit_source_concept_id,
  {{ resolve_concept('admit_source_code', 'SNOMED') }}        AS admitted_from_concept_id,
  admit_source_code                                            AS admitted_from_source_value,
  {{ resolve_concept('discharge_disposition_code', 'SNOMED') }} AS discharged_to_concept_id,
  discharge_disposition_code                                   AS discharged_to_source_value,
  LAG(ABS(FARM_FINGERPRINT(resource_id))) OVER (
    PARTITION BY ABS(FARM_FINGERPRINT(patient_id))
    ORDER BY SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(period_start, 1, 19))
  ) AS preceding_visit_occurrence_id
FROM {{ ref('stg_encounter') }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY resource_id ORDER BY ingestion_timestamp DESC) = 1
