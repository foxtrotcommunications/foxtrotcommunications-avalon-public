{{ config(materialized='view') }}

-- Staging: flatten forge-core Procedure from child tables only
-- All values from frg__root__raw_1 and descendants
--
-- Tree: root → raw_1 → code1 → code1__codi1, perf1, subj1, enco1

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

FROM {{ source('forge_procedure', 'frg__root') }} r

{{ forge_join('raw', 'forge_procedure', 'frg__root__raw_1', 'r', 'frg__root') }}
{{ forge_join('code_cc', 'forge_procedure', 'frg__root__raw_1__code1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('code_c', 'forge_procedure', 'frg__root__raw_1__code1__codi1', 'code_cc', 'frg__root__raw_1__code1') }}
{{ forge_join('perf', 'forge_procedure', 'frg__root__raw_1__perf1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('subj', 'forge_procedure', 'frg__root__raw_1__subj1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('enc_ref', 'forge_procedure', 'frg__root__raw_1__enco1', 'raw', 'frg__root__raw_1') }}
