{{ config(materialized='view') }}

-- Staging: flatten forge-core Encounter from child tables only
--
-- Tree (depth):
--   frg__root (2) → encounter_raw (3) → encounter_class (4)
--                                      → encounter_period (4)
--                                      → encounter_participant (4) → encounter_part_indiv (5)
--                                      → encounter_subject (4)

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  raw.status,
  REPLACE(COALESCE(subj.reference, ''), 'urn:uuid:', '') AS patient_id,
  cls.code AS class_code,
  peri.start AS period_start,
  peri.`end` AS period_end,
  part_ind.reference AS participant_individual_reference,
  part_ind.display AS participant_individual_display

FROM {{ source('forge_encounter', 'frg__root') }} r

{{ forge_join('raw',      'forge_encounter', 'encounter_raw',         'r',    2) }}
{{ forge_join('cls',      'forge_encounter', 'encounter_class',       'raw',  3) }}
{{ forge_join('peri',     'forge_encounter', 'encounter_period',      'raw',  3) }}
{{ forge_join('part',     'forge_encounter', 'encounter_participant', 'raw',  3) }}
{{ forge_join('part_ind', 'forge_encounter', 'encounter_part_indiv',  'part', 4) }}
{{ forge_join('subj',     'forge_encounter', 'encounter_subject',     'raw',  3) }}
