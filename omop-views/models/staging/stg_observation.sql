{{ config(materialized='view') }}

-- Staging: flatten forge-core Observation from child tables only
--
-- Tree (depth):
--   frg__root (2) → observation_raw (3) → observation_code (4) → observation_code_coding (5)
--                                        → observation_value (4)
--                                        → observation_subject (4)
--                                        → observation_encounter (4)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  REPLACE(COALESCE(subj.reference, ''), 'urn:uuid:', '') AS patient_id,
  REPLACE(COALESCE(enc_ref.reference, ''), 'urn:uuid:', '') AS encounter_id,
  raw.effective_date_time AS effective_date,
  code_c.code AS code,
  code_c.display AS code_display,
  val.value AS value_quantity,
  val.unit AS value_unit

FROM {{ source('forge_observation', 'frg__root') }} r

{{ forge_join('raw',     'forge_observation', 'observation_raw',          'r',      2) }}
{{ forge_join('code_cc', 'forge_observation', 'observation_code',         'raw',    3) }}
{{ forge_join('code_c',  'forge_observation', 'observation_code_coding',  'code_cc', 4) }}
{{ forge_join('val',     'forge_observation', 'observation_value',        'raw',    3) }}
{{ forge_join('subj',    'forge_observation', 'observation_subject',      'raw',    3) }}
{{ forge_join('enc_ref', 'forge_observation', 'observation_encounter',    'raw',    3) }}
