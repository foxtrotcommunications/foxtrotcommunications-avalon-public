-- Data quality: ensure observation_period end_date >= start_date
-- This catches cases where encounter period_end is before period_start

SELECT
  observation_period_id,
  person_id,
  observation_period_start_date,
  observation_period_end_date
FROM {{ ref('omop_observation_period') }}
WHERE observation_period_end_date < observation_period_start_date
