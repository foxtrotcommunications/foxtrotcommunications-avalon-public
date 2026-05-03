{{ config(materialized='view') }}

-- Staging: flatten forge-core Encounter from child tables only
--
-- Tree (depth):
--   frg__root (2) → encounter_raw (3) → encounter_class (4)
--                                      → encounter_period (4)
--                                      → encounter_participant (4) → encounter_part_indiv (5)
--                                      → encounter_subject (4)
--
-- Encounter.hospitalization (admitSource, dischargeDisposition) is optional in FHIR R4
-- and sparse in synthetic data. Enable with var enable_hospitalization=true once
-- the sub-tables exist: run discover_table_map.py to confirm table names first.

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
  part_ind.display AS participant_individual_display,
  serv.reference AS service_provider_reference,
  serv.display AS service_provider_display
  {% if var('enable_hospitalization', false) %}
  -- Hospitalization fields: only populated for inpatient encounters
  , admit_c.code    AS admit_source_code
  , admit_c.system  AS admit_source_system
  , disch_c.code    AS discharge_disposition_code
  , disch_c.system  AS discharge_disposition_system
  {% else %}
  -- Hospitalization disabled (set enable_hospitalization: true after verifying sub-table names)
  , CAST(NULL AS STRING) AS admit_source_code
  , CAST(NULL AS STRING) AS admit_source_system
  , CAST(NULL AS STRING) AS discharge_disposition_code
  , CAST(NULL AS STRING) AS discharge_disposition_system
  {% endif %}

FROM {{ source('forge_encounter', 'frg__root') }} r

{{ forge_join('raw',      'forge_encounter', 'encounter_raw',         'r',    2) }}
{{ forge_join('cls',      'forge_encounter', 'encounter_class',       'raw',  3) }}
{{ forge_join('peri',     'forge_encounter', 'encounter_period',      'raw',  3) }}
{{ forge_join('part',     'forge_encounter', 'encounter_participant', 'raw',  3) }}
{{ forge_join('part_ind', 'forge_encounter', 'encounter_part_indiv',  'part', 4) }}
{{ forge_join('subj',     'forge_encounter', 'encounter_subject',          'raw',  3) }}
{{ forge_join('serv',     'forge_encounter', 'encounter_service_provider', 'raw',  3) }}
{% if var('enable_hospitalization', false) %}
{{ forge_join('hosp',    'forge_encounter', 'encounter_hosp',         'raw',   3) }}
{{ forge_join('admit',   'forge_encounter', 'encounter_admit_source', 'hosp',  4) }}
{{ forge_join('admit_c', 'forge_encounter', 'encounter_admit_coding', 'admit', 5) }}
{{ forge_join('disch',   'forge_encounter', 'encounter_disch_disp',   'hosp',  4) }}
{{ forge_join('disch_c', 'forge_encounter', 'encounter_disch_coding', 'disch', 5) }}
{% endif %}
