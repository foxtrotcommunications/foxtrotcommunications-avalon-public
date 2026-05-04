-- Cross-model consistency: every visit should fall within the patient's
-- observation period (since observation_period is derived from encounters)
-- A failure here indicates the observation_period aggregation logic missed
-- some encounters, or a visit has a person_id mismatch

SELECT
  v.visit_occurrence_id,
  v.person_id,
  v.visit_start_date,
  op.observation_period_start_date,
  op.observation_period_end_date
FROM {{ ref('omop_visit_occurrence') }} v
JOIN {{ ref('omop_observation_period') }} op
  ON op.person_id = v.person_id
WHERE v.visit_start_date < op.observation_period_start_date
   OR v.visit_start_date > DATE_ADD(op.observation_period_end_date, INTERVAL 1 DAY)
