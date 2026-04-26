{{ config(materialized='view') }}

-- Staging: flatten forge-core Patient from child tables only
-- frg__root is used ONLY for ingestion_hash/timestamp (join key)
-- All values come from frg__root__raw_1 and descendants
--
-- Tree: root → raw_1 → name1, addr1, exte1 → exte1__exte1 → valu1

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

{{ forge_join('raw', 'forge_patient', 'frg__root__raw_1', 'r', 'frg__root') }}
{{ forge_join('ext', 'forge_patient', 'frg__root__raw_1__exte1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('sub_ext', 'forge_patient', 'frg__root__raw_1__exte1__exte1', 'ext', 'frg__root__raw_1__exte1') }}
{{ forge_join('sub_ext_val', 'forge_patient', 'frg__root__raw_1__exte1__exte1__valu1', 'sub_ext', 'frg__root__raw_1__exte1__exte1') }}
