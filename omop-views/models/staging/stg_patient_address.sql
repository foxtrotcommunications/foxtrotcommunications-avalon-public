{{ config(materialized='view') }}

-- Staging: flatten forge-core Patient.address from child sub-table
-- root provides ingestion_hash/timestamp (join anchor)
-- Patient.address contains city, state, postal_code, country, line
--
-- Tree (depth):
--   root (2) → patient_raw (3) → patient_address (4)
--
-- The extension column contains embedded geolocation data (lat/long)
-- which we extract here for downstream use.

WITH address_raw AS (
  SELECT
    r.ingestion_hash,
    r.ingestion_timestamp,
    raw.id AS patient_id,
    addr.city,
    addr.state,
    addr.postal_code,
    addr.country,
    addr.line AS address_line,
    addr.extension AS geo_extension
  FROM {{ source('forge_patient', 'root') }} r
  {{ forge_join('raw',  'forge_patient', 'patient_raw',     'r',   2) }}
  {{ forge_join('addr', 'forge_patient', 'patient_address', 'raw', 3) }}
  WHERE addr.city IS NOT NULL OR addr.state IS NOT NULL
)

SELECT
  ingestion_hash,
  ingestion_timestamp,
  patient_id,
  city,
  state,
  postal_code,
  country,
  address_line,
  -- Extract latitude from geolocation extension JSON
  SAFE_CAST(
    JSON_VALUE(
      JSON_QUERY_ARRAY(geo_extension)[SAFE_OFFSET(0)],
      '$.extension[0].valueDecimal'
    ) AS FLOAT64
  ) AS latitude,
  -- Extract longitude from geolocation extension JSON
  SAFE_CAST(
    JSON_VALUE(
      JSON_QUERY_ARRAY(geo_extension)[SAFE_OFFSET(0)],
      '$.extension[1].valueDecimal'
    ) AS FLOAT64
  ) AS longitude
FROM address_raw
