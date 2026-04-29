{{ config(materialized='table') }}

-- OMOP CDM 5.4 — MEASUREMENT (numeric observations only)

SELECT
  ABS(FARM_FINGERPRINT(resource_id)) AS measurement_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  {{ resolve_concept('code', 'LOINC') }} AS measurement_concept_id,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(effective_date, 1, 10)) AS measurement_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(effective_date, 1, 19)) AS measurement_datetime,
  CAST(NULL AS STRING) AS measurement_time,
  44818702 AS measurement_type_concept_id,
  0 AS operator_concept_id,
  SAFE_CAST(value_quantity AS FLOAT64) AS value_as_number,
  0 AS value_as_concept_id,
  {{ resolve_concept('value_ucum_code', 'UCUM') }} AS unit_concept_id,
  CAST(NULL AS FLOAT64) AS range_low,
  CAST(NULL AS FLOAT64) AS range_high,
  CAST(NULL AS INT64) AS provider_id,
  ABS(FARM_FINGERPRINT(encounter_id)) AS visit_occurrence_id,
  CAST(NULL AS INT64) AS visit_detail_id,
  code AS measurement_source_value,
  {{ resolve_source_concept('code', 'LOINC') }} AS measurement_source_concept_id,
  value_unit AS unit_source_value,
  value_quantity AS value_source_value
FROM {{ ref('stg_observation') }}
WHERE value_quantity IS NOT NULL
  AND SAFE_CAST(value_quantity AS FLOAT64) IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY patient_id, encounter_id, code
  ORDER BY effective_date DESC
) = 1
