{{ config(materialized='table') }}

-- OMOP CDM 5.4 — LOCATION
-- Maps forge-core Patient.address → OMOP location
-- Deduplicated to one row per unique city/state/zip combination.
-- location_id is deterministic via FARM_FINGERPRINT so omop_person
-- can compute its own location_id without a JOIN at build time.

WITH patient_addresses AS (
  SELECT
    city,
    state,
    postal_code,
    country,
    address_line,
    latitude,
    longitude,
    ROW_NUMBER() OVER (
      PARTITION BY IFNULL(city, ''), IFNULL(state, ''), IFNULL(postal_code, '')
      ORDER BY ingestion_timestamp DESC
    ) AS rn
  FROM {{ ref('stg_patient_address') }}
)

SELECT
  ABS(FARM_FINGERPRINT(
    CONCAT(IFNULL(city, ''), '|', IFNULL(state, ''), '|', IFNULL(postal_code, ''))
  )) AS location_id,
  -- OMOP CDM 5.4: address_1 = street address (first line from FHIR array)
  JSON_VALUE(address_line, '$[0]') AS address_1,
  CAST(NULL AS STRING) AS address_2,
  city,
  state,
  postal_code AS zip,
  CAST(NULL AS STRING) AS county,
  CONCAT(IFNULL(city, ''), ', ', IFNULL(state, ''), ' ', IFNULL(postal_code, '')) AS location_source_value,
  CAST(NULL AS INT64) AS country_concept_id,
  country AS country_source_value,
  latitude,
  longitude
FROM patient_addresses
WHERE rn = 1
