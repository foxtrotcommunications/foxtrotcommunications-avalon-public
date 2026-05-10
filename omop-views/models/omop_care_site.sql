{{ config(materialized='table') }}

-- OMOP CDM 5.4 — CARE_SITE
-- Derived from Encounter.serviceProvider references within existing
-- Forge-ingested encounter data.
--
-- Synthea encodes organization references as:
--   "Organization?identifier=https://github.com/synthetichealth/synthea|<uuid>"
-- We extract the org identifier and display name.
--
-- TODO: When Forge ingests the Organization resource directly, enrich
-- this model with address, phone, and location_id from the resource.

WITH service_providers AS (
  SELECT DISTINCT
    service_provider_reference AS org_reference,
    service_provider_display AS org_name
  FROM {{ ref('stg_encounter') }}
  WHERE service_provider_reference IS NOT NULL
    AND service_provider_reference != ''
),

deduped AS (
  SELECT
    org_reference,
    MAX(org_name) AS org_name
  FROM service_providers
  GROUP BY org_reference
)

SELECT
  ABS(FARM_FINGERPRINT(org_reference)) AS care_site_id,
  org_name AS care_site_name,
  CAST(NULL AS INT64) AS place_of_service_concept_id,
  CAST(NULL AS INT64) AS location_id,
  org_reference AS care_site_source_value,
  CAST(NULL AS STRING) AS place_of_service_source_value
FROM deduped
