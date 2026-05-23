{{ config(materialized='table') }}

-- OMOP CDM 5.4 — PROVIDER
-- Derived from references embedded in Encounter.participant.individual
-- and MedicationRequest.requester within existing Forge-ingested data.
--
-- Synthea encodes practitioner references as:
--   "Practitioner?identifier=http://hl7.org/fhir/sid/us-npi|9999867390"
-- We extract the NPI and display name from these references.
--
-- TODO: When Forge ingests the Practitioner resource directly, enrich
-- this model with specialty, gender, and address from the resource.

WITH encounter_providers AS (
  SELECT DISTINCT
    participant_individual_reference AS provider_reference,
    participant_individual_display AS provider_name
  FROM {{ ref('stg_encounter') }}
  WHERE participant_individual_reference IS NOT NULL
),

medication_providers AS (
  SELECT DISTINCT
    requester_reference AS provider_reference,
    CAST(NULL AS STRING) AS provider_name
  FROM {{ ref('stg_medication_request') }}
  WHERE requester_reference IS NOT NULL
    AND requester_reference != ''
),

all_providers AS (
  SELECT provider_reference, provider_name FROM encounter_providers
  UNION DISTINCT
  SELECT provider_reference, provider_name FROM medication_providers
),

-- Deduplicate: prefer the record with a display name
deduped AS (
  SELECT
    provider_reference,
    MAX(provider_name) AS provider_name
  FROM all_providers
  GROUP BY provider_reference
)

SELECT
  ABS(FARM_FINGERPRINT(provider_reference)) AS provider_id,
  provider_name AS provider_name,
  -- Extract NPI from Synthea-style references like:
  -- "Practitioner?identifier=http://hl7.org/fhir/sid/us-npi|9999867390"
  CASE
    WHEN provider_reference LIKE '%us-npi|%'
    THEN SUBSTR(provider_reference,
                STRPOS(provider_reference, 'us-npi|') + 7)
    ELSE CAST(NULL AS STRING)
  END AS npi,
  CAST(NULL AS INT64) AS dea,
  CAST(NULL AS INT64) AS specialty_concept_id,
  CAST(NULL AS INT64) AS care_site_id,
  CAST(NULL AS INT64) AS year_of_birth,
  CAST(NULL AS INT64) AS gender_concept_id,
  provider_reference AS provider_source_value,
  CAST(NULL AS STRING) AS specialty_source_value,
  CAST(NULL AS INT64) AS specialty_source_concept_id,
  CAST(NULL AS STRING) AS gender_source_value,
  CAST(NULL AS INT64) AS gender_source_concept_id
FROM deduped
