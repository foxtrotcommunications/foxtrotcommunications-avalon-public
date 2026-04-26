-- Data quality: every person in omop_death must exist in omop_person

SELECT
  d.person_id
FROM {{ ref('omop_death') }} d
LEFT JOIN {{ ref('omop_person') }} p ON p.person_id = d.person_id
WHERE p.person_id IS NULL
