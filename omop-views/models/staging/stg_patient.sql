{{ config(materialized='view') }}

-- Staging: flatten forge-core Patient sub-tables into a single view
-- Sources: frg__root → frg__root__raw_1 → name1, addr1, exte1, mari1

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  r.resource_id,
  r.patient_id,
  r.synthea_run_id,
  COALESCE(r.cohort_id, 'coh_legacy') AS cohort_id,
  raw.gender,
  raw.birth_date,
  raw.deceased_date_time,
  ext.url AS extension_url,
  sub_ext.url AS sub_extension_url,
  sub_ext_val.code AS extension_value_code,
  sub_ext_val.display AS extension_value_display

FROM {{ source('forge_patient', 'frg__root') }} r

{{ forge_join('raw', 'forge_patient', 'frg__root__raw_1', 'r', 'frg__root') }}
{{ forge_join('ext', 'forge_patient', 'frg__root__raw_1__exte1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('sub_ext', 'forge_patient', 'frg__root__raw_1__exte1__exte1', 'ext', 'frg__root__raw_1__exte1') }}
{{ forge_join('sub_ext_val', 'forge_patient', 'frg__root__raw_1__exte1__exte1__valu1', 'sub_ext', 'frg__root__raw_1__exte1__exte1') }}
