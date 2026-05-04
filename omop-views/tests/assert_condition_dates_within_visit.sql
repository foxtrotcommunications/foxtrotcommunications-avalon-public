{{ config(severity='warn') }}
-- Cross-model temporal consistency: condition onset should be within
-- a reasonable window of the associated visit
-- Uses a 365-day tolerance because FHIR Condition.onsetDateTime may
-- represent a chronic condition diagnosed years before a given encounter

SELECT
  c.condition_occurrence_id,
  c.condition_start_date,
  v.visit_start_date,
  v.visit_end_date,
  DATE_DIFF(c.condition_start_date, v.visit_start_date, DAY) AS days_diff
FROM {{ ref('omop_condition_occurrence') }} c
JOIN {{ ref('omop_visit_occurrence') }} v
  ON v.visit_occurrence_id = c.visit_occurrence_id
WHERE c.condition_start_date IS NOT NULL
  AND v.visit_start_date IS NOT NULL
  AND (c.condition_start_date < DATE_SUB(v.visit_start_date, INTERVAL 365 DAY)
    OR c.condition_start_date > DATE_ADD(COALESCE(v.visit_end_date, v.visit_start_date), INTERVAL 365 DAY))
