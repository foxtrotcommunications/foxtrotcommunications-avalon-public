-- Data quality: payer plan end date must be >= start date
-- Both dates come from EOB billablePeriod (MIN/MAX aggregation)

SELECT
  payer_plan_period_id,
  person_id,
  payer_plan_period_start_date,
  payer_plan_period_end_date
FROM {{ ref('omop_payer_plan_period') }}
WHERE payer_plan_period_end_date < payer_plan_period_start_date
