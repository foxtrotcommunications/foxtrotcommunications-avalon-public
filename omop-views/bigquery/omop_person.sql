-- ─────────────────────────────────────────────────────────────────
-- omop_person — OMOP CDM 5.4
--
-- Source:  FHIR Patient → forge-core `patient` table
-- Target:  OMOP PERSON (https://ohdsi.github.io/CommonDataModel/cdm54.html#PERSON)
--
-- Placeholders: {project}, {dataset}
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW `{project}.{dataset}.omop_person` AS

WITH patient_latest AS (
  SELECT *
  FROM `{project}.{dataset}.patient`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY ingestion_timestamp DESC) = 1
),

-- Race/Ethnicity from flattened US Core extensions
patient_extensions AS (
  SELECT
    patient_id,
    MAX(CASE
      WHEN extension_url = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-race'
        AND sub_extension_url = 'ombCategory'
      THEN extension_value_code
    END) AS race_code,
    MAX(CASE
      WHEN extension_url = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-race'
        AND sub_extension_url = 'ombCategory'
      THEN extension_value_display
    END) AS race_display,
    MAX(CASE
      WHEN extension_url = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity'
        AND sub_extension_url = 'ombCategory'
      THEN extension_value_code
    END) AS ethnicity_code,
    MAX(CASE
      WHEN extension_url = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity'
        AND sub_extension_url = 'ombCategory'
      THEN extension_value_display
    END) AS ethnicity_display
  FROM patient_latest
  GROUP BY patient_id
)

SELECT
  ABS(FARM_FINGERPRINT(p.patient_id)) AS person_id,
  CASE p.gender
    WHEN 'male' THEN 8507
    WHEN 'female' THEN 8532
    WHEN 'other' THEN 44814653
    WHEN 'unknown' THEN 8551
    ELSE 0
  END AS gender_concept_id,
  EXTRACT(YEAR FROM SAFE.PARSE_DATE('%Y-%m-%d', p.birth_date)) AS year_of_birth,
  EXTRACT(MONTH FROM SAFE.PARSE_DATE('%Y-%m-%d', p.birth_date)) AS month_of_birth,
  EXTRACT(DAY FROM SAFE.PARSE_DATE('%Y-%m-%d', p.birth_date)) AS day_of_birth,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%d', p.birth_date) AS birth_datetime,
  CASE pe.race_code
    WHEN '2106-3' THEN 8527   -- White
    WHEN '2054-5' THEN 8516   -- Black or African American
    WHEN '2028-9' THEN 8515   -- Asian
    WHEN '1002-5' THEN 8657   -- American Indian or Alaska Native
    WHEN '2076-8' THEN 8557   -- Native Hawaiian or Other Pacific Islander
    ELSE 0
  END AS race_concept_id,
  CASE pe.ethnicity_code
    WHEN '2135-2' THEN 38003563  -- Hispanic or Latino
    WHEN '2186-5' THEN 38003564  -- Not Hispanic or Latino
    ELSE 0
  END AS ethnicity_concept_id,
  CAST(NULL AS INT64) AS location_id,
  CAST(NULL AS INT64) AS provider_id,
  CAST(NULL AS INT64) AS care_site_id,
  p.patient_id AS person_source_value,
  p.gender AS gender_source_value,
  0 AS gender_source_concept_id,
  pe.race_display AS race_source_value,
  0 AS race_source_concept_id,
  pe.ethnicity_display AS ethnicity_source_value,
  0 AS ethnicity_source_concept_id
FROM patient_latest p
LEFT JOIN patient_extensions pe ON pe.patient_id = p.patient_id;
