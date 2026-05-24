{{ config(materialized='table') }}

-- ECCDM Entity: CancerConditionAtDiagnosis
-- A cancer diagnosis asserted at a specific point in time.
-- Uses OMOP concept_ancestor hierarchy (descendants of 443392)
-- to identify malignant neoplastic conditions from SNOMED codes.
-- Depends on: omop_condition_occurrence, omop_person

SELECT
  co.condition_occurrence_id,
  co.person_id,
  co.condition_concept_id,
  co.condition_source_value,
  c.concept_name                                    AS condition_name,
  co.condition_start_date                           AS diagnosis_date,
  co.condition_start_datetime                       AS diagnosis_datetime,
  co.condition_end_date,
  co.condition_end_datetime,
  co.condition_type_concept_id,
  co.condition_status_concept_id,
  co.condition_status_source_value,
  co.condition_source_concept_id,
  co.visit_occurrence_id,
  co.provider_id,

  -- Age at diagnosis
  DATE_DIFF(
    co.condition_start_date,
    DATE(p.year_of_birth, COALESCE(p.month_of_birth, 1), COALESCE(p.day_of_birth, 1)),
    YEAR
  )                                                 AS age_at_diagnosis

FROM {{ ref('omop_condition_occurrence') }} co
JOIN {{ ref('omop_person') }} p
  ON p.person_id = co.person_id
JOIN {{ source('omop_vocab', 'concept') }} c
  ON c.concept_id = co.condition_concept_id
WHERE co.condition_concept_id IN (
  SELECT ca.descendant_concept_id
  FROM {{ source('omop_vocab', 'concept_ancestor') }} ca
  WHERE ca.ancestor_concept_id = 443392  -- Malignant neoplastic disease
)
