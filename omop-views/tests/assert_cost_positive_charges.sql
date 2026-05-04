-- Data quality: cost amounts should be non-negative
-- CMS BlueButton adjudication values are always >= 0

SELECT
  cost_id,
  total_charge,
  total_paid
FROM {{ ref('omop_cost') }}
WHERE (total_charge IS NOT NULL AND total_charge < 0)
   OR (total_paid IS NOT NULL AND total_paid < 0)
