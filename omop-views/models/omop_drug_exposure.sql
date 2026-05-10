{{ config(materialized='table') }}

-- OMOP CDM 5.4 — DRUG_EXPOSURE
-- Sources: MedicationRequest (prescriptions) + Immunization (vaccines)
-- IG Ref: StructureMap/MedicationMap, StructureMap/ImmunizationMap

WITH medication_exposures AS (
  SELECT
    ABS(FARM_FINGERPRINT(CONCAT(patient_id, '|', encounter_id, '|', med_code))) AS drug_exposure_id,
    ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
    med_code AS drug_code,
    'RxNorm' AS drug_vocab,
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(authored_on, 1, 10)) AS drug_exposure_start_date,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(authored_on, 1, 19)) AS drug_exposure_start_datetime,
    CAST(NULL AS DATE) AS drug_exposure_end_date,
    CAST(NULL AS TIMESTAMP) AS drug_exposure_end_datetime,
    CAST(NULL AS DATE) AS verbatim_end_date,
    38000177 AS drug_type_concept_id,  -- Prescription written
    CAST(NULL AS STRING) AS stop_reason,
    CAST(NULL AS INT64) AS refills,
    SAFE_CAST(dose_quantity_value AS FLOAT64) AS quantity,
    CAST(NULL AS INT64) AS days_supply,
    sig,
    route_code,
    route_display,
    CAST(NULL AS STRING) AS lot_number,
    COALESCE(ABS(FARM_FINGERPRINT(requester_reference)), 0) AS provider_id,
    ABS(FARM_FINGERPRINT(encounter_id)) AS visit_occurrence_id,
    CAST(NULL AS INT64) AS visit_detail_id,
    med_code AS drug_source_value,
    route_display AS route_source_value,
    CAST(NULL AS STRING) AS dose_unit_source_value,
    patient_id AS _patient_id,
    encounter_id AS _encounter_id,
    authored_on AS _sort_date
  FROM {{ ref('stg_medication_request') }}
  WHERE med_code IS NOT NULL
),

immunization_exposures AS (
  SELECT
    ABS(FARM_FINGERPRINT(CONCAT(patient_id, '|', encounter_id, '|', vaccine_code))) AS drug_exposure_id,
    ABS(FARM_FINGERPRINT(patient_id)) AS person_id,
    vaccine_code AS drug_code,
    'CVX' AS drug_vocab,
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(occurrence_date_time, 1, 10)) AS drug_exposure_start_date,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(occurrence_date_time, 1, 19)) AS drug_exposure_start_datetime,
    -- Immunizations are point-in-time: start = end
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(occurrence_date_time, 1, 10)) AS drug_exposure_end_date,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S', SUBSTR(occurrence_date_time, 1, 19)) AS drug_exposure_end_datetime,
    CAST(NULL AS DATE) AS verbatim_end_date,
    32818 AS drug_type_concept_id,  -- EHR administration record
    CAST(NULL AS STRING) AS stop_reason,
    CAST(NULL AS INT64) AS refills,
    CAST(NULL AS FLOAT64) AS quantity,
    CAST(NULL AS INT64) AS days_supply,
    CAST(NULL AS STRING) AS sig,
    CAST(NULL AS STRING) AS route_code,
    CAST(NULL AS STRING) AS route_display,
    CAST(NULL AS STRING) AS lot_number,
    0 AS provider_id,
    ABS(FARM_FINGERPRINT(encounter_id)) AS visit_occurrence_id,
    CAST(NULL AS INT64) AS visit_detail_id,
    vaccine_code AS drug_source_value,
    CAST(NULL AS STRING) AS route_source_value,
    CAST(NULL AS STRING) AS dose_unit_source_value,
    patient_id AS _patient_id,
    encounter_id AS _encounter_id,
    occurrence_date_time AS _sort_date
  FROM {{ ref('stg_immunization') }}
  WHERE vaccine_code IS NOT NULL
    AND status = 'completed'
),

all_exposures AS (
  SELECT * FROM medication_exposures
  UNION ALL
  SELECT * FROM immunization_exposures
)

SELECT
  drug_exposure_id,
  person_id,
  {{ resolve_concept('cm_drug', 0) }} AS drug_concept_id,
  drug_exposure_start_date,
  drug_exposure_start_datetime,
  drug_exposure_end_date,
  drug_exposure_end_datetime,
  verbatim_end_date,
  drug_type_concept_id,
  stop_reason,
  refills,
  quantity,
  days_supply,
  sig,
  {{ resolve_concept('cm_route', 0) }} AS route_concept_id,
  lot_number,
  provider_id,
  visit_occurrence_id,
  visit_detail_id,
  drug_source_value,
  {{ resolve_source_concept('sc_drug', 0) }} AS drug_source_concept_id,
  route_source_value,
  dose_unit_source_value
FROM all_exposures exp
{{ resolve_concept_join('cm_drug', 'exp.drug_code', 'RxNorm') }}
{{ resolve_concept_join('cm_route', 'exp.route_code', 'SNOMED') }}
{{ resolve_source_join('sc_drug', 'exp.drug_code', 'RxNorm') }}
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY _patient_id, _encounter_id, drug_source_value
  ORDER BY _sort_date DESC
) = 1
