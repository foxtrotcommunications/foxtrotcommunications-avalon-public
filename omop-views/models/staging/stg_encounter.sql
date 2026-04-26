{{ config(materialized='view') }}

-- Staging: flatten forge-core Encounter sub-tables
-- Sources: frg__root → raw_1 → clas1, peri1, part1 → part1__indi1

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  r.resource_id,
  r.patient_id,
  r.encounter_id,
  r.synthea_run_id,
  COALESCE(r.cohort_id, 'coh_legacy') AS cohort_id,
  raw.status,
  cls.code AS class_code,
  peri.start AS period_start,
  peri.`end` AS period_end,
  part_ind.reference AS participant_individual_reference,
  part_ind.display AS participant_individual_display

FROM {{ source('forge_encounter', 'frg__root') }} r

{{ forge_join('raw', 'forge_encounter', 'frg__root__raw_1', 'r', 'frg__root') }}
{{ forge_join('cls', 'forge_encounter', 'frg__root__raw_1__clas1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('peri', 'forge_encounter', 'frg__root__raw_1__peri1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('part', 'forge_encounter', 'frg__root__raw_1__part1', 'raw', 'frg__root__raw_1') }}
{{ forge_join('part_ind', 'forge_encounter', 'frg__root__raw_1__part1__indi1', 'part', 'frg__root__raw_1__part1') }}
