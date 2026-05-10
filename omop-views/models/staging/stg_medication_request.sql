{{ config(materialized='view') }}

-- Staging: flatten forge-core MedicationRequest from child tables only
--
-- Tree (depth):
--   root (2) → med_request_raw (3) → med_request_med_concept (4)
--                                          → med_request_med_coding (5)
--                                        → med_request_subject (4)
--                                        → med_request_encounter (4)
--
-- MedicationRequest.dosageInstruction.route is optional in FHIR R4 and
-- sparse in synthetic data. Enable with var enable_dosage_route=true once
-- the sub-tables exist: run discover_table_map.py to confirm table names first.

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  REPLACE(COALESCE(subj.reference, ''), 'urn:uuid:', '') AS patient_id,
  REPLACE(COALESCE(enc_ref.reference, ''), 'urn:uuid:', '') AS encounter_id,
  raw.authored_on,
  med_c.code    AS med_code,
  med_c.display AS med_display,
  med_c.system  AS med_system
  {% if var('enable_dosage_route', false) %}
  -- Route of administration (e.g., SNOMED 47625008 = intravenous)
  , route_c.code    AS route_code
  , route_c.system  AS route_system
  , route_c.display AS route_display
  {% else %}
  -- Dosage route disabled (set enable_dosage_route: true after verifying sub-table names)
  , CAST(NULL AS STRING) AS route_code
  , CAST(NULL AS STRING) AS route_system
  , CAST(NULL AS STRING) AS route_display
  {% endif %}
  -- Requester (prescriber → provider_id)
  , REPLACE(COALESCE(reqr.reference, ''), 'urn:uuid:', '') AS requester_reference
  -- Dosage instruction text (sig)
  , dosa.text AS sig
  -- Dosage dose quantity
  , dose_qty.value AS dose_quantity_value

FROM {{ source('forge_medication_request', 'root__root') }} r

{{ forge_join('raw',     'forge_medication_request', 'med_request_raw',         'r',   2) }}
{{ forge_join('med',     'forge_medication_request', 'med_request_med_concept', 'raw', 3) }}
{{ forge_join('med_c',   'forge_medication_request', 'med_request_med_coding',  'med', 4) }}
{{ forge_join('subj',    'forge_medication_request', 'med_request_subject',     'raw', 3) }}
{{ forge_join('enc_ref', 'forge_medication_request', 'med_request_encounter',   'raw', 3) }}
{{ forge_join('reqr',    'forge_medication_request', 'med_request_requester',   'raw', 3) }}
{{ forge_join('dosa',    'forge_medication_request', 'med_request_dosage',      'raw', 3) }}
{{ forge_join('dose_dr', 'forge_medication_request', 'med_request_dosage_dose_rate', 'dosa', 4) }}
{{ forge_join('dose_qty','forge_medication_request', 'med_request_dosage_dose_qty',  'dose_dr', 5) }}
{% if var('enable_dosage_route', false) %}
{{ forge_join('route',   'forge_medication_request', 'med_request_dosage_route',  'dosa', 4) }}
{{ forge_join('route_c', 'forge_medication_request', 'med_request_route_coding',  'route', 5) }}
{% endif %}
