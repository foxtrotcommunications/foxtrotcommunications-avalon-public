-- rt_recent_labs: Laboratory results from the last 48 hours
-- All values from raw_json, with critical value flagging.

{{ config(materialized='view') }}

SELECT
  resource_id AS observation_id,
  patient_id,
  encounter_id,
  JSON_VALUE(raw_json, '$.code.coding[0].code') AS loinc_code,
  JSON_VALUE(raw_json, '$.code.coding[0].display') AS lab_name,
  JSON_VALUE(raw_json, '$.code.text') AS lab_text,
  SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) AS result_value,
  JSON_VALUE(raw_json, '$.valueQuantity.unit') AS result_unit,
  JSON_VALUE(raw_json, '$.valueString') AS result_string,
  CAST(JSON_VALUE(raw_json, '$.effectiveDateTime') AS TIMESTAMP) AS result_time,
  JSON_VALUE(raw_json, '$.status') AS status,
  JSON_VALUE(raw_json, '$.category[0].coding[0].code') AS category,
  -- Critical value flags based on clinical thresholds
  CASE
    WHEN JSON_VALUE(raw_json, '$.code.coding[0].display') LIKE '%Potassium%'
      AND SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) < 3.5
      THEN 'CRITICAL_LOW'
    WHEN JSON_VALUE(raw_json, '$.code.coding[0].display') LIKE '%Potassium%'
      AND SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) > 5.0
      THEN 'CRITICAL_HIGH'
    WHEN JSON_VALUE(raw_json, '$.code.coding[0].display') LIKE '%Troponin%'
      AND SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) > 0.04
      THEN 'CRITICAL_HIGH'
    WHEN JSON_VALUE(raw_json, '$.code.coding[0].display') LIKE '%Glucose%'
      AND SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) < 70
      THEN 'CRITICAL_LOW'
    WHEN JSON_VALUE(raw_json, '$.code.coding[0].display') LIKE '%Glucose%'
      AND SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) > 300
      THEN 'CRITICAL_HIGH'
    WHEN JSON_VALUE(raw_json, '$.code.coding[0].display') LIKE '%Hemoglobin%'
      AND SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) < 7.0
      THEN 'CRITICAL_LOW'
    WHEN JSON_VALUE(raw_json, '$.code.coding[0].display') LIKE '%Creatinine%'
      AND SAFE_CAST(JSON_VALUE(raw_json, '$.valueQuantity.value') AS FLOAT64) > 4.0
      THEN 'CRITICAL_HIGH'
    ELSE 'NORMAL'
  END AS critical_flag,
  _ingested_date
FROM {{ source('bellows_staging', 'raw_observation') }}
WHERE JSON_VALUE(raw_json, '$.category[0].coding[0].code') = 'laboratory'
  AND CAST(JSON_VALUE(raw_json, '$.effectiveDateTime') AS DATE)
      >= DATE_SUB(CURRENT_DATE(), INTERVAL 2 DAY)
