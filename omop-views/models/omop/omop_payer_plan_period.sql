{{ config(materialized='table') }}

-- OMOP CDM 5.4 — PAYER_PLAN_PERIOD
-- Maps forge-core ExplanationOfBenefit → OMOP payer_plan_period
-- Uses billablePeriod for actual coverage dates (not ingestion_timestamp)
-- Uses contained Coverage resource for plan type and payor display

WITH eob_coverage AS (
  SELECT
    REPLACE(COALESCE(pat.reference, ''), 'urn:uuid:', '') AS patient_id,
    ins_org.display AS insurer_display,
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(bill.start, 1, 10)) AS period_start,
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(bill.`end`, 1, 10)) AS period_end,
    cont_type.text AS plan_type,
    cont_payo.display AS payor_display

  FROM {{ source('forge_eob', 'root__root') }} r

  {{ forge_join('raw',        'forge_eob', 'eob_raw',              'r',    2) }}
  {{ forge_join('pat',        'forge_eob', 'eob_patient',          'raw',  3) }}
  {{ forge_join('ins_org',    'forge_eob', 'eob_insurer',          'raw',  3) }}
  {{ forge_join('bill',       'forge_eob', 'eob_billable_period',  'raw',  3) }}
  {{ forge_join('cont',       'forge_eob', 'eob_contained',        'raw',  3) }}
  {{ forge_join('cont_type',  'forge_eob', 'eob_contained_type',   'cont', 4) }}
  {{ forge_join('cont_payo',  'forge_eob', 'eob_contained_payor',  'cont', 4) }}

  WHERE bill.start IS NOT NULL
)

SELECT
  ROW_NUMBER() OVER (ORDER BY patient_id, insurer_display) AS payer_plan_period_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  MIN(period_start) AS payer_plan_period_start_date,
  MAX(COALESCE(period_end, period_start)) AS payer_plan_period_end_date,
  CAST(NULL AS INT64) AS payer_concept_id,
  insurer_display AS payer_source_value,
  0 AS payer_source_concept_id,
  CAST(NULL AS INT64) AS plan_concept_id,
  MAX(plan_type) AS plan_source_value,
  0 AS plan_source_concept_id,
  CAST(NULL AS INT64) AS sponsor_concept_id,
  MAX(payor_display) AS sponsor_source_value,
  0 AS sponsor_source_concept_id,
  CAST(NULL AS STRING) AS family_source_value,
  CAST(NULL AS INT64) AS stop_reason_concept_id,
  CAST(NULL AS STRING) AS stop_reason_source_value,
  0 AS stop_reason_source_concept_id

FROM eob_coverage
WHERE insurer_display IS NOT NULL
GROUP BY patient_id, insurer_display
