-- ─────────────────────────────────────────────────────────────────
-- omop_drug_exposure — OMOP CDM 5.4
--
-- Source:  FHIR MedicationRequest → forge-core `medication_request` table
-- Target:  OMOP DRUG_EXPOSURE
--
-- Placeholders: {project}, {dataset}
-- ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW `{project}.{dataset}.omop_drug_exposure` AS

SELECT
  ABS(FARM_FINGERPRINT(resource_id)) AS drug_exposure_id,
  ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
  0 AS drug_concept_id,  -- requires vocabulary JOIN for RxNorm → OMOP mapping
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(authored_on, 1, 10)) AS drug_exposure_start_date,
  SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(authored_on, 1, 19)) AS drug_exposure_start_datetime,
  CAST(NULL AS DATE) AS drug_exposure_end_date,
  CAST(NULL AS TIMESTAMP) AS drug_exposure_end_datetime,
  CAST(NULL AS DATE) AS verbatim_end_date,
  38000177 AS drug_type_concept_id,  -- Prescription written
  CAST(NULL AS STRING) AS stop_reason,
  CAST(NULL AS INT64) AS refills,
  CAST(NULL AS FLOAT64) AS quantity,
  CAST(NULL AS INT64) AS days_supply,
  CAST(NULL AS STRING) AS sig,
  0 AS route_concept_id,
  CAST(NULL AS STRING) AS lot_number,
  CAST(NULL AS INT64) AS provider_id,
  ABS(FARM_FINGERPRINT(encounter_id)) AS visit_occurrence_id,
  CAST(NULL AS INT64) AS visit_detail_id,
  med_code AS drug_source_value,
  0 AS drug_source_concept_id,
  CAST(NULL AS STRING) AS route_source_value,
  CAST(NULL AS STRING) AS dose_unit_source_value
FROM `{project}.{dataset}.medication_request`
WHERE med_code IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY patient_id, encounter_id, med_code
  ORDER BY authored_on DESC
) = 1;
