{{ config(materialized='view') }}

-- Staging: flatten forge-core Observation from child tables only
--
-- Tree (depth):
--   frg__root (2) → observation_raw (3) → observation_code (4) → observation_code_coding (5)
--                                        → observation_value_codeable_concept (4) [valu1]
--                                            → observation_value_cc_coding (5)    [valu1__codi1]
--                                        → observation_value_quantity (4)         [valu2]
--                                        → observation_subject (4)
--                                        → observation_encounter (4)
--
-- Two value types are pulled and surfaced as separate columns:
--   value_quantity / value_unit / value_ucum_code — from valueQuantity (valu2)
--   value_codeable_concept_code                   — from valueCodeableConcept (valu1__codi1)
-- omop_measurement consumes the quantity columns; omop_observation the coded ones.

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  REPLACE(COALESCE(subj.reference, ''), 'urn:uuid:', '') AS patient_id,
  REPLACE(COALESCE(enc_ref.reference, ''), 'urn:uuid:', '') AS encounter_id,
  raw.effective_date_time AS effective_date,
  code_c.code         AS code,
  code_c.display      AS code_display,
  -- valueQuantity fields (numeric lab results — maps to omop_measurement)
  val_qty.value       AS value_quantity,
  val_qty.unit        AS value_unit,
  val_qty.code        AS value_ucum_code,   -- UCUM machine code e.g. "mm[Hg]"
  val_qty.system      AS value_unit_system,
  -- valueCodeableConcept fields (coded results — maps to omop_observation)
  val_cc.code         AS value_codeable_concept_code,
  val_cc.display      AS value_codeable_concept_display,
  val_cc.system       AS value_codeable_concept_system,
  -- valueString (free-text results — maps to omop_observation.value_as_string)
  raw.value_string

FROM {{ source('forge_observation', 'frg__root') }} r

{{ forge_join('raw',     'forge_observation', 'observation_raw',          'r',      2) }}
{{ forge_join('code_cc', 'forge_observation', 'observation_code',         'raw',    3) }}
{{ forge_join('code_c',  'forge_observation', 'observation_code_coding',  'code_cc', 4) }}
-- valueQuantity (numeric): valu2
{{ forge_join('val_qty', 'forge_observation', 'observation_value_quantity', 'raw',  3) }}
-- valueCodeableConcept.coding (coded): valu1 → valu1__codi1
{{ forge_join('val_cc',  'forge_observation', 'observation_value_cc_coding', 'raw', 3) }}
{{ forge_join('subj',    'forge_observation', 'observation_subject',      'raw',    3) }}
{{ forge_join('enc_ref', 'forge_observation', 'observation_encounter',    'raw',    3) }}
