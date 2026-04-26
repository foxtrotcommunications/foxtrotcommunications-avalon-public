-- ─────────────────────────────────────────────────────────────────
-- omop_observation_period — OMOP CDM 5.4
--
-- Source:  FHIR Encounter (aggregated) → forge-core `encounter` table
-- Target:  OMOP OBSERVATION_PERIOD
--
-- Placeholders: {project}, {dataset}
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW `{project}.{dataset}.omop_observation_period` AS

SELECT
  ROW_NUMBER() OVER (ORDER BY patient_id) AS observation_period_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  MIN(SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(period_start, 1, 10))) AS observation_period_start_date,
  MAX(COALESCE(
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(period_end, 1, 10)),
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(period_start, 1, 10))
  )) AS observation_period_end_date,
  44814724 AS period_type_concept_id  -- EHR
FROM `{project}.{dataset}.encounter`
GROUP BY patient_id;
