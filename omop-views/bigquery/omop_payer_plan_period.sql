-- omop_payer_plan_period — OMOP CDM 5.4
-- Source: FHIR ExplanationOfBenefit → forge-core `explanation_of_benefit` table
-- Placeholders: {project}, {dataset}

CREATE OR REPLACE VIEW `{project}.{dataset}.omop_payer_plan_period` AS

SELECT DISTINCT
  ABS(FARM_FINGERPRINT(CONCAT(patient_id, '-', payer_name))) AS payer_plan_period_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  MIN(SAFE.PARSE_DATE('%Y-%m-%d', effective_date)) OVER (
    PARTITION BY patient_id, payer_name
  ) AS payer_plan_period_start_date,
  MAX(SAFE.PARSE_DATE('%Y-%m-%d', effective_date)) OVER (
    PARTITION BY patient_id, payer_name
  ) AS payer_plan_period_end_date,
  0 AS payer_concept_id,
  payer_name AS payer_source_value,
  0 AS plan_concept_id,
  CAST(NULL AS STRING) AS plan_source_value,
  CAST(NULL AS STRING) AS sponsor_source_value,
  CAST(NULL AS STRING) AS family_source_value,
  0 AS stop_reason_concept_id,
  CAST(NULL AS STRING) AS stop_reason_source_value,
  patient_id AS person_source_value
FROM `{project}.{dataset}.explanation_of_benefit`
WHERE payer_name IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY patient_id, payer_name
  ORDER BY ingestion_timestamp DESC
) = 1;
