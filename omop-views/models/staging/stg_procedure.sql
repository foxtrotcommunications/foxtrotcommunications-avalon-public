{{ config(materialized='view') }}

-- Staging: flatten forge-core Procedure sub-tables
-- Sources: frg__root → raw_1 → perf1 (performedPeriod)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  r.resource_id,
  r.patient_id,
  r.encounter_id,
  r.code,
  r.code_display,
  r.synthea_run_id,
  COALESCE(r.cohort_id, 'coh_legacy') AS cohort_id,
  raw.status,
  perf.start AS performed_start,
  perf.`end` AS performed_end

FROM {{ source('forge_procedure', 'frg__root') }} r

{{ forge_join('raw', 'forge_procedure', 'frg__root__raw_1', 'r', 'frg__root') }}
{{ forge_join('perf', 'forge_procedure', 'frg__root__raw_1__perf1', 'raw', 'frg__root__raw_1') }}
