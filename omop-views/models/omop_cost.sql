{{ config(materialized='table') }}

-- OMOP CDM 5.4 — COST
-- Maps forge-core Claim item-level costs → OMOP cost
-- Links to visit_occurrence, condition_occurrence, procedure_occurrence
-- via the claim's encounter reference

SELECT
  ROW_NUMBER() OVER (ORDER BY c.ingestion_hash, c.resource_id) AS cost_id,
  ABS(FARM_FINGERPRINT(c.encounter_id)) AS cost_event_id,
  'Visit' AS cost_domain_id,
  31968 AS cost_type_concept_id,
  44818668 AS currency_concept_id,
  SAFE_CAST(c.item_net_value AS FLOAT64) AS total_charge,

  -- Payment from EOB (if available)
  SAFE_CAST(eob.payment_amount AS FLOAT64) AS total_paid,

  -- Payer amounts from EOB total
  SAFE_CAST(eob.total_amount AS FLOAT64) AS paid_by_payer,
  CAST(NULL AS FLOAT64) AS paid_by_patient,
  CAST(NULL AS FLOAT64) AS paid_patient_copay,
  CAST(NULL AS FLOAT64) AS paid_patient_coinsurance,
  CAST(NULL AS FLOAT64) AS paid_patient_deductible,
  CAST(NULL AS FLOAT64) AS paid_by_primary,
  CAST(NULL AS FLOAT64) AS paid_ingredient_cost,
  CAST(NULL AS FLOAT64) AS paid_dispensing_fee,
  CAST(NULL AS INT64) AS payer_plan_period_id,
  CAST(NULL AS FLOAT64) AS amount_allowed,
  0 AS revenue_code_concept_id,
  CAST(NULL AS STRING) AS revenue_code_source_value,
  0 AS drg_concept_id,
  CAST(NULL AS STRING) AS drg_source_value

FROM {{ ref('stg_claim') }} c
LEFT JOIN (
  SELECT
    patient_id,
    total_amount,
    payment_amount,
    ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY ingestion_timestamp DESC) AS rn
  FROM {{ ref('stg_explanation_of_benefit') }}
) eob
  ON eob.patient_id = c.patient_id
  AND eob.rn = 1
WHERE c.item_net_value IS NOT NULL
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY c.patient_id, c.encounter_id, c.item_product_code
  ORDER BY c.ingestion_timestamp DESC
) = 1
