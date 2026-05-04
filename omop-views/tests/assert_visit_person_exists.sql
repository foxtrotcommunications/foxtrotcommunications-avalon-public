-- Cross-model referential integrity: every visit must reference a valid person
-- Supplements the schema.yml relationship test with diagnostic output

SELECT
  v.visit_occurrence_id,
  v.person_id
FROM {{ ref('omop_visit_occurrence') }} v
LEFT JOIN {{ ref('omop_person') }} p ON p.person_id = v.person_id
WHERE p.person_id IS NULL
