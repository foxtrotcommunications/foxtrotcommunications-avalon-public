-- rt_recent_vitals: Vital signs from the last 24 hours
-- Includes blood pressure component extraction from raw_json.

{{ config(materialized='view') }}

SELECT
  resource_id AS observation_id,
  patient_id,
  encounter_id,
  JSON_VALUE(raw_json, '$.code.coding[0].code') AS loinc_code,
  JSON_VALUE(raw_json, '$.code.coding[0].display') AS vital_name,
  SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) AS value,
  JSON_VALUE(raw_json, '$.valueQuantity.unit') AS unit,
  SAFE_CAST(JSON_VALUE(raw_json, '$.effectiveDateTime') AS TIMESTAMP) AS recorded_time,
  -- Blood pressure panels have component values
  SAFE_CAST(JSON_VALUE(raw_json, '$.component[0].valueQuantity.value') AS FLOAT64) AS systolic,
  SAFE_CAST(JSON_VALUE(raw_json, '$.component[1].valueQuantity.value') AS FLOAT64) AS diastolic,
  _ingested_date
FROM {{ source('bellows_staging', 'raw_observation') }}
WHERE JSON_VALUE(raw_json, '$.category[0].coding[0].code') = 'vital-signs'
  AND SAFE_CAST(JSON_VALUE(raw_json, '$.effectiveDateTime') AS TIMESTAMP)
      >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
