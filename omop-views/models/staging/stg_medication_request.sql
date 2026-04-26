{{ config(materialized='view') }}

-- Staging: flatten forge-core MedicationRequest from child tables only
-- All values from frg__root__raw_1 and descendants
--
-- Tree: root → raw_1 → medi1 → medi1__codi1, subj1, enco1

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

{{ forge_join('raw', 'forge_medication_request', 'frg__root__raw_1', 'r', 'frg__root') }}
{{ forge_join('med', 'forge_medication_request', 'frg__root__raw_1__medi1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('med_c', 'forge_medication_request', 'frg__root__raw_1__medi1__codi1', 'med', 'frg__root__raw_1__medi1') }}
{{ forge_join('subj', 'forge_medication_request', 'frg__root__raw_1__subj1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('enc_ref', 'forge_medication_request', 'frg__root__raw_1__enco1', 'raw', 'frg__root__raw_1') }}
