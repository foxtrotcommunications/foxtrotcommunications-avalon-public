{{ config(materialized='view') }}

-- Staging: flatten forge-core Patient from child tables only
-- frg__root provides ingestion_hash/timestamp (join anchor)
-- All clinical values from child sub-tables
--
-- Tree (depth):
--   frg__root (2) → patient_raw (3) → patient_extension (4)
--                                      → patient_ext_ext (5) → patient_ext_ext_val (6)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  raw.id AS patient_id,
  raw.gender,
  raw.birth_date,
  raw.deceased_date_time,
  ext.url AS extension_url,
  sub_ext.url AS sub_extension_url,
  sub_ext_val.code AS extension_value_code,
  sub_ext_val.display AS extension_value_display

FROM {{ source('forge_patient', 'frg__root') }} r

{{ forge_join('raw',         'forge_patient', 'patient_raw',         'r',       2) }}
{{ forge_join('ext',         'forge_patient', 'patient_extension',   'raw',     3) }}
{{ forge_join('sub_ext',     'forge_patient', 'patient_ext_ext',     'ext',     4) }}
{{ forge_join('sub_ext_val', 'forge_patient', 'patient_ext_ext_val', 'sub_ext', 5) }}
