{{ config(materialized='view') }}

-- ECCDM Entity: CancerPatient
-- The subject of care, affected by one or more cancer conditions.
-- Depends on: omop_person, omop_observation_period, omop_condition_occurrence

SELECT DISTINCT
  p.person_id,
  p.gender_concept_id,
  p.year_of_birth,
  p.month_of_birth,
  p.day_of_birth,
  DATE(p.year_of_birth, COALESCE(p.month_of_birth, 1), COALESCE(p.day_of_birth, 1))
                                                    AS date_of_birth,
  p.race_concept_id,
  p.race_source_value,
  p.ethnicity_concept_id,
  p.ethnicity_source_value,
  p.person_source_value,
  op.observation_period_start_date                  AS first_observation_date,
  op.observation_period_end_date                    AS last_observation_date,
  d.death_date,
  CASE WHEN d.death_date IS NOT NULL THEN TRUE ELSE FALSE END AS is_deceased
FROM {{ ref('omop_person') }} p
LEFT JOIN {{ ref('omop_observation_period') }} op
  ON op.person_id = p.person_id
LEFT JOIN {{ ref('omop_death') }} d
  ON d.person_id = p.person_id
WHERE p.person_id IN (
  SELECT DISTINCT person_id
  FROM {{ ref('omop_condition_occurrence') }}
  WHERE condition_source_value LIKE 'C%'
    AND condition_source_value NOT LIKE 'C44%'
)
