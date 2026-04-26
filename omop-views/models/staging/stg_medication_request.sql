{{ config(materialized='view') }}

-- Staging: flatten forge-core MedicationRequest from child tables only
--
-- Tree (depth):
--   frg__root (2) → med_request_raw (3) → med_request_med_concept (4)
--                                          → med_request_med_coding (5)
--                                        → med_request_subject (4)
--                                        → med_request_encounter (4)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  REPLACE(COALESCE(subj.reference, ''), 'urn:uuid:', '') AS patient_id,
  REPLACE(COALESCE(enc_ref.reference, ''), 'urn:uuid:', '') AS encounter_id,
  raw.authored_on,
  med_c.code AS med_code,
  med_c.display AS med_display,
  med_c.system AS med_system

FROM {{ source('forge_medication_request', 'frg__root') }} r

{{ forge_join('raw',     'forge_medication_request', 'med_request_raw',         'r',   2) }}
{{ forge_join('med',     'forge_medication_request', 'med_request_med_concept', 'raw', 3) }}
{{ forge_join('med_c',   'forge_medication_request', 'med_request_med_coding',  'med', 4) }}
{{ forge_join('subj',    'forge_medication_request', 'med_request_subject',     'raw', 3) }}
{{ forge_join('enc_ref', 'forge_medication_request', 'med_request_encounter',   'raw', 3) }}
