{{ config(materialized='view') }}

-- ECCDM Entity: OverallCancerTreatmentResponse
-- Evaluation of how a cancer condition responds to treatment.
-- Based on tumor markers (PSA, CEA, CA-125, CA-19-9) and RECIST assessments.
-- Depends on: omop_measurement, eccdm_cancer_patient
--
-- Note: Standard Synthea modules do not generate explicit RECIST assessments.
-- Custom Synthea modules may populate RECIST codes directly.
-- This view captures tumor marker observations that indicate treatment response.

SELECT
  m.measurement_id,
  m.person_id,
  m.measurement_concept_id,
  m.measurement_source_value                        AS loinc_code,
  m.value_as_number                                 AS numeric_value,
  m.unit_source_value                               AS unit,
  m.value_as_concept_id,
  m.value_source_value                              AS coded_value,
  m.measurement_date                                AS assessment_date,
  m.measurement_datetime                            AS assessment_datetime,
  m.visit_occurrence_id,

  -- Classify response marker type
  CASE
    WHEN m.measurement_source_value = '2857-1'  THEN 'PSA'
    WHEN m.measurement_source_value = '2039-6'  THEN 'CEA'
    WHEN m.measurement_source_value = '10334-1' THEN 'CA-125'
    WHEN m.measurement_source_value = '24108-3' THEN 'CA-19-9'
    ELSE 'other_marker'
  END                                               AS response_marker_type

FROM {{ ref('omop_measurement') }} m
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = m.person_id
WHERE m.measurement_source_value IN (
  '2857-1',   -- PSA (prostate)
  '2039-6',   -- CEA (colorectal, lung)
  '10334-1',  -- CA-125 (ovarian)
  '24108-3'   -- CA-19-9 (pancreatic)
)
