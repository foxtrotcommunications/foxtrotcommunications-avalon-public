{{ config(materialized='view') }}

-- Staging: flatten forge-core Procedure from child tables only
--
-- Tree (depth):
--   root (2) → procedure_raw (3) → procedure_code (4) → procedure_code_coding (5)
--                                      → procedure_performed (4)
--                                      → procedure_subject (4)
--                                      → procedure_encounter (4)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  REPLACE(COALESCE(subj.reference, ''), 'urn:uuid:', '') AS patient_id,
  REPLACE(COALESCE(enc_ref.reference, ''), 'urn:uuid:', '') AS encounter_id,
  code_c.code AS code,
  code_c.display AS code_display,
  raw.status,
  perf.start AS performed_start,
  perf.`end` AS performed_end

FROM {{ source('forge_procedure', 'root') }} r

{{ forge_join('raw',     'forge_procedure', 'procedure_raw',          'r',      2) }}
{{ forge_join('code_cc', 'forge_procedure', 'procedure_code',         'raw',    3) }}
{{ forge_join('code_c',  'forge_procedure', 'procedure_code_coding',  'code_cc', 4) }}
{{ forge_join('perf',    'forge_procedure', 'procedure_performed',    'raw',    3) }}
{{ forge_join('subj',    'forge_procedure', 'procedure_subject',      'raw',    3) }}
{{ forge_join('enc_ref', 'forge_procedure', 'procedure_encounter',    'raw',    3) }}
