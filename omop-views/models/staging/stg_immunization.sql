{{ config(materialized='view') }}

-- Staging: flatten forge-core Immunization from child tables
--
-- Tree (depth):
--   root (2) → immunization_raw (3) → immunization_vaccine_code (4)
--                                             → immunization_vaccine_coding (5)
--                                          → immunization_patient (4)
--                                          → immunization_encounter (4)
--
-- Maps to omop_drug_exposure (via UNION in that model).
-- Vaccine codes use CVX vocabulary (http://hl7.org/fhir/sid/cvx).

SELECT
  r.ingestion_hash,
  r.ingestion_timestamp,
  raw.id AS resource_id,
  raw.status,
  REPLACE(COALESCE(pati.reference, ''), 'urn:uuid:', '') AS patient_id,
  REPLACE(COALESCE(enc_ref.reference, ''), 'urn:uuid:', '') AS encounter_id,
  raw.occurrence_date_time,
  vacc_c.code    AS vaccine_code,
  vacc_c.display AS vaccine_display,
  vacc_c.system  AS vaccine_system,
  raw.primary_source

FROM {{ source('forge_immunization', 'root') }} r

{{ forge_join('raw',     'forge_immunization', 'immunization_raw',            'r',   2) }}
{{ forge_join('vacc',    'forge_immunization', 'immunization_vaccine_code',   'raw', 3) }}
{{ forge_join('vacc_c',  'forge_immunization', 'immunization_vaccine_coding', 'vacc', 4) }}
{{ forge_join('pati',    'forge_immunization', 'immunization_patient',        'raw', 3) }}
{{ forge_join('enc_ref', 'forge_immunization', 'immunization_encounter',      'raw', 3) }}
