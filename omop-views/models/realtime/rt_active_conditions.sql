-- rt_active_conditions: Active diagnoses for current inpatients
-- All clinical data extracted from raw_json only.

{{ config(materialized='view') }}

SELECT
  resource_id AS condition_id,
  patient_id,
  encounter_id,
  JSON_VALUE(raw_json, '$.code.coding[0].system') AS code_system,
  JSON_VALUE(raw_json, '$.code.coding[0].code') AS snomed_code,
  JSON_VALUE(raw_json, '$.code.coding[0].display') AS condition_name,
  JSON_VALUE(raw_json, '$.code.text') AS condition_text,
  JSON_VALUE(raw_json, '$.clinicalStatus.coding[0].code') AS clinical_status,
  JSON_VALUE(raw_json, '$.verificationStatus.coding[0].code') AS verification_status,
  JSON_VALUE(raw_json, '$.category[0].coding[0].code') AS category,
  SAFE_CAST(JSON_VALUE(raw_json, '$.onsetDateTime') AS TIMESTAMP) AS onset_date,
  SAFE_CAST(JSON_VALUE(raw_json, '$.recordedDate') AS TIMESTAMP) AS recorded_date,
  _ingested_date
FROM {{ source('bellows_staging', 'raw_condition') }}
WHERE JSON_VALUE(raw_json, '$.clinicalStatus.coding[0].code') = 'active'
