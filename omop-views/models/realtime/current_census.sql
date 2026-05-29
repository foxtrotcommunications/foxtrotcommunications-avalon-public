-- rt_current_census: Current inpatient census
-- All clinical data extracted from raw_json only.
-- Top-level columns are pipeline metadata only.

{{ config(materialized='view') }}

WITH encounters AS (
  SELECT
    resource_id AS encounter_id,
    patient_id,
    JSON_VALUE(raw_json, '$.class.code') AS encounter_class,
    JSON_VALUE(raw_json, '$.type[0].coding[0].display') AS encounter_type,
    JSON_VALUE(raw_json, '$.status') AS status,
    CAST(JSON_VALUE(raw_json, '$.period.start') AS TIMESTAMP) AS admit_time,
    DATE_DIFF(
      CURRENT_DATE(),
      DATE(CAST(JSON_VALUE(raw_json, '$.period.start') AS TIMESTAMP)),
      DAY
    ) AS los_days,
    JSON_VALUE(raw_json, '$.serviceProvider.display') AS facility,
    JSON_VALUE(raw_json, '$.location[0].location.display') AS location,
    _ingested_date
  FROM {{ source('bellows_staging', 'raw_encounter') }}
  WHERE JSON_VALUE(raw_json, '$.class.code') = 'IMP'
    AND JSON_VALUE(raw_json, '$.status') = 'in-progress'
),

patients AS (
  SELECT
    resource_id AS patient_id,
    JSON_VALUE(raw_json, '$.name[0].given[0]') AS first_name,
    JSON_VALUE(raw_json, '$.name[0].family') AS last_name,
    SAFE_CAST(LEFT(JSON_VALUE(raw_json, '$.birthDate'), 10) AS DATE) AS birth_date,
    DATE_DIFF(
      CURRENT_DATE(),
      SAFE_CAST(LEFT(JSON_VALUE(raw_json, '$.birthDate'), 10) AS DATE),
      YEAR
    ) AS age,
    JSON_VALUE(raw_json, '$.gender') AS gender
  FROM {{ source('bellows_staging', 'raw_patient') }}
)

SELECT
  e.encounter_id,
  e.patient_id,
  p.first_name,
  p.last_name,
  p.age,
  p.gender,
  e.encounter_class,
  e.encounter_type,
  e.status,
  e.admit_time,
  e.los_days,
  e.facility,
  e.location,
  CASE
    WHEN LOWER(COALESCE(e.encounter_type, '')) LIKE '%icu%'
      OR LOWER(COALESCE(e.encounter_type, '')) LIKE '%critical%' THEN 'ICU'
    WHEN LOWER(COALESCE(e.encounter_type, '')) LIKE '%emergency%' THEN 'ED'
    WHEN LOWER(COALESCE(e.encounter_type, '')) LIKE '%surgical%' THEN 'Surgical'
    ELSE 'Med/Surg'
  END AS unit,
  MOD(ABS(FARM_FINGERPRINT(e.encounter_id)), 30) + 1 AS bed_number,
  e._ingested_date
FROM encounters e
LEFT JOIN patients p ON e.patient_id = p.patient_id
