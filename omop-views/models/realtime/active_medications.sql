-- rt_active_medications: Active medication orders for current inpatients
-- All clinical data extracted from raw_json only.

{{ config(materialized='view') }}

SELECT
  resource_id AS medication_request_id,
  patient_id,
  encounter_id,
  JSON_VALUE(raw_json, '$.status') AS status,
  JSON_VALUE(raw_json, '$.medicationCodeableConcept.coding[0].code') AS rxnorm_code,
  JSON_VALUE(raw_json, '$.medicationCodeableConcept.coding[0].display') AS medication_name,
  JSON_VALUE(raw_json, '$.medicationCodeableConcept.text') AS medication_text,
  CAST(JSON_VALUE(raw_json, '$.authoredOn') AS TIMESTAMP) AS order_date,
  JSON_VALUE(raw_json, '$.dosageInstruction[0].text') AS dosage_instruction,
  JSON_VALUE(raw_json, '$.dosageInstruction[0].timing.code.text') AS frequency,
  JSON_VALUE(raw_json, '$.dosageInstruction[0].route.coding[0].display') AS route,
  JSON_VALUE(raw_json, '$.requester.display') AS ordering_provider,
  JSON_VALUE(raw_json, '$.intent') AS intent,
  _ingested_date
FROM {{ source('bellows_staging', 'raw_medicationrequest') }}
WHERE JSON_VALUE(raw_json, '$.status') IN ('active', 'on-hold')
