-- Contract test: ensure financial staging models produce rows from forge_join
-- Extends assert_staging_not_empty.sql to cover claim and EOB models
-- that feed omop_cost and omop_payer_plan_period

SELECT 'stg_claim' AS model, COUNT(*) AS row_count
FROM {{ ref('stg_claim') }} WHERE resource_id IS NOT NULL HAVING COUNT(*) = 0
UNION ALL
SELECT 'stg_explanation_of_benefit', COUNT(*)
FROM {{ ref('stg_explanation_of_benefit') }} WHERE resource_id IS NOT NULL HAVING COUNT(*) = 0
