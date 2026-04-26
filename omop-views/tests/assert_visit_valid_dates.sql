-- Data quality: ensure visit end_date >= start_date where both are non-null

SELECT
  visit_occurrence_id,
  person_id,
  visit_start_date,
  visit_end_date
FROM {{ ref('omop_visit_occurrence') }}
WHERE visit_end_date IS NOT NULL
  AND visit_start_date IS NOT NULL
  AND visit_end_date < visit_start_date
