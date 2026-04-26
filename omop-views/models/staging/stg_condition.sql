{{ config(materialized='view') }}

-- Staging: flatten forge-core Condition sub-tables
-- Sources: frg__root → raw_1 (clinical_status, verification_status)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  r.resource_id,
  r.patient_id,
  r.encounter_id,
  r.effective_date,
  r.code,
  r.code_display,
  r.synthea_run_id,
  COALESCE(r.cohort_id, 'coh_legacy') AS cohort_id,
  raw.clinical_status

FROM {{ source('forge_condition', 'frg__root') }} r

{{ forge_join('raw', 'forge_condition', 'frg__root__raw_1', 'r', 'frg__root') }}
