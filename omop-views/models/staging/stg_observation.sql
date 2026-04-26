{{ config(materialized='view') }}

-- Staging: forge-core Observation (root table only, no sub-tables needed)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  r.resource_id,
  r.patient_id,
  r.encounter_id,
  r.effective_date,
  r.code,
  r.code_display,
  r.value_quantity,
  r.value_unit,
  r.synthea_run_id,
  COALESCE(r.cohort_id, 'coh_legacy') AS cohort_id

FROM {{ source('forge_observation', 'frg__root') }} r
