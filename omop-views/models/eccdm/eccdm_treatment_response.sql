{{ config(materialized='table') }}

-- ECCDM Entity: OverallCancerTreatmentResponse
-- Evaluation of how a cancer condition responds to treatment.
-- Captures tumor markers and key lab values for cancer patients.
-- Note: Standard Synthea does not generate explicit RECIST or tumor markers.
-- This table captures lab trends that clinicians use to monitor treatment response.
-- Depends on: omop_measurement, eccdm_cancer_patient

SELECT
  m.measurement_id,
  m.person_id,
  m.measurement_concept_id,
  m.measurement_source_value                        AS loinc_code,
  c.concept_name                                    AS measurement_name,
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
    WHEN m.measurement_source_value = '718-7'   THEN 'Hemoglobin'
    WHEN m.measurement_source_value = '26464-8' THEN 'Leukocytes'
    WHEN m.measurement_source_value = '33914-3' THEN 'eGFR'
    WHEN m.measurement_source_value = '4548-4'  THEN 'HbA1c'
    WHEN m.measurement_source_value = '17861-6' THEN 'Calcium'
    WHEN m.measurement_source_value = '2160-0'  THEN 'Creatinine'
    ELSE 'other_lab'
  END                                               AS response_marker_type

FROM {{ ref('omop_measurement') }} m
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = m.person_id
LEFT JOIN {{ source('omop_vocab', 'concept') }} c
  ON c.concept_id = m.measurement_concept_id
WHERE m.value_as_number IS NOT NULL
