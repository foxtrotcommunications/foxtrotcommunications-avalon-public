{{ config(materialized='view') }}

-- Staging: flatten forge-core Condition from child tables only
--
-- Tree (depth):
--   frg__root (2) → condition_raw (3) → condition_code (4) → condition_code_coding (5)
--                                      → condition_subject (4)
--                                      → condition_encounter (4)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  REPLACE(COALESCE(subj.reference, ''), 'urn:uuid:', '') AS patient_id,
  REPLACE(COALESCE(enc_ref.reference, ''), 'urn:uuid:', '') AS encounter_id,
  raw.onset_date_time AS effective_date,
  code_c.code AS code,
  code_c.display AS code_display,
  raw.clinical_status

FROM {{ source('forge_condition', 'frg__root') }} r

{{ forge_join('raw',     'forge_condition', 'condition_raw',          'r',      2) }}
{{ forge_join('code_cc', 'forge_condition', 'condition_code',         'raw',    3) }}
{{ forge_join('code_c',  'forge_condition', 'condition_code_coding',  'code_cc', 4) }}
{{ forge_join('subj',    'forge_condition', 'condition_subject',      'raw',    3) }}
{{ forge_join('enc_ref', 'forge_condition', 'condition_encounter',    'raw',    3) }}
