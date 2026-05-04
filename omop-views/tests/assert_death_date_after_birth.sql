{{ config(severity='warn') }}
-- Cross-model temporal consistency: death must occur after birth
-- Catches data quality issues in Patient.deceasedDateTime or Patient.birthDate

SELECT
  d.person_id,
  p.year_of_birth,
  d.death_date
FROM {{ ref('omop_death') }} d
JOIN {{ ref('omop_person') }} p ON p.person_id = d.person_id
WHERE EXTRACT(YEAR FROM d.death_date) < p.year_of_birth
