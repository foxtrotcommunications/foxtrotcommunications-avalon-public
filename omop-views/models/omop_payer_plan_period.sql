{{ config(materialized='table') }}

-- OMOP CDM 5.4 — PAYER_PLAN_PERIOD
-- Maps forge-core ExplanationOfBenefit → OMOP payer_plan_period
-- Derives coverage period from the earliest/latest EOB per patient+insurer

SELECT
  ROW_NUMBER() OVER (ORDER BY patient_id, insurer_display) AS payer_plan_period_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  payer_plan_period_start_date,
  payer_plan_period_end_date,
  CAST(NULL AS INT64) AS payer_concept_id,
  insurer_display AS payer_source_value,
  0 AS payer_source_concept_id,
  CAST(NULL AS INT64) AS plan_concept_id,
  CAST(NULL AS STRING) AS plan_source_value,
  0 AS plan_source_concept_id,
  CAST(NULL AS INT64) AS sponsor_concept_id,
  CAST(NULL AS STRING) AS sponsor_source_value,
  0 AS sponsor_source_concept_id,
  CAST(NULL AS STRING) AS family_source_value,
  CAST(NULL AS INT64) AS stop_reason_concept_id,
  CAST(NULL AS STRING) AS stop_reason_source_value,
  0 AS stop_reason_source_concept_id

FROM (
  SELECT
    patient_id,
    insurer_display,
    MIN(SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(ingestion_timestamp, 1, 10)))
      AS payer_plan_period_start_date,
    MAX(SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(ingestion_timestamp, 1, 10)))
      AS payer_plan_period_end_date
  FROM {{ ref('stg_explanation_of_benefit') }}
  WHERE insurer_display IS NOT NULL
  GROUP BY patient_id, insurer_display
)
