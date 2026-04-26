{{ config(materialized='view') }}

-- Staging: flatten forge-core MedicationRequest sub-tables
-- Sources: frg__root → raw_1 → medi1 → medi1__codi1 (RxNorm code)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  r.resource_id,
  r.patient_id,
  r.encounter_id,
  r.synthea_run_id,
  COALESCE(r.cohort_id, 'coh_legacy') AS cohort_id,
  raw.authored_on,
  med_c.code AS med_code,
  med_c.display AS med_display,
  med_c.system AS med_system

FROM {{ source('forge_medication_request', 'frg__root') }} r

{{ forge_join('raw', 'forge_medication_request', 'frg__root__raw_1', 'r', 'frg__root') }}
{{ forge_join('med', 'forge_medication_request', 'frg__root__raw_1__medi1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('med_c', 'forge_medication_request', 'frg__root__raw_1__medi1__codi1', 'med', 'frg__root__raw_1__medi1') }}
