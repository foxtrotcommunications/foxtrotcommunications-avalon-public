-- Data quality: after dedup (QUALIFY ROW_NUMBER by patient/encounter/code),
-- no duplicate (person_id, visit_occurrence_id, observation_source_value) should remain

SELECT
  person_id,
  visit_occurrence_id,
  observation_source_value,
  COUNT(*) AS dupes
FROM {{ ref('omop_observation') }}
GROUP BY person_id, visit_occurrence_id, observation_source_value
HAVING COUNT(*) > 1
