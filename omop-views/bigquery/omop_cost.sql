-- omop_cost — OMOP CDM 5.4
-- Source: FHIR Claim (item-level) + ExplanationOfBenefit + BB2 cost reference
-- Target: OMOP COST (https://ohdsi.github.io/CommonDataModel/cdm54.html#COST)
--
-- Each row = one claim line item with procedure-level cost.
-- Patient cost-sharing (copay, coinsurance, deductible) is calibrated using
-- CMS Blue Button 2.0 published statistics via the bb2_cost_reference table.
--
-- Dependencies:
--   - {dataset}.claim                          — forge-core flat claim table
--   - {dataset}.explanation_of_benefit         — forge-core flat EOB table
--   - {dataset}.bb2_cost_reference             — Medicare cost fractions (static lookup)
--   - {dataset}.omop_payer_plan_period         — must be created first
--   - fhir_normalized_claim.frg__root__raw_1__item1        — claim line items (forge sub-table)
--   - fhir_normalized_claim.frg__root__raw_1__item1__net1  — line item costs (forge sub-table)
--   - fhir_normalized_claim.frg__root__raw_1__item1__prod1__codi1 — item procedure codes
--
-- Placeholders: {project}, {dataset}

CREATE OR REPLACE VIEW `{project}.{dataset}.omop_cost` AS

SELECT
  ABS(FARM_FINGERPRINT(CONCAT(c.resource_id, '-', item.sequence))) AS cost_id,
  ABS(FARM_FINGERPRINT(c.patient_id)) AS person_id,
  ABS(FARM_FINGERPRINT(c.encounter_id)) AS cost_event_id,
  1147084 AS cost_event_field_concept_id,
  0 AS cost_concept_id,
  32810 AS cost_type_concept_id,
  44818668 AS currency_concept_id,

  -- Item-level cost from Claim.item[].net
  SAFE_CAST(net.value AS FLOAT64) AS total_charge,
  SAFE_CAST(net.value AS FLOAT64) AS total_cost,

  -- BB2-calibrated Medicare cost fractions
  ROUND(COALESCE(SAFE_CAST(net.value AS FLOAT64), bb2.charge_p50)
        * COALESCE(bb2.avg_payer_fraction, 0.78), 2) AS total_paid,
  ROUND(COALESCE(SAFE_CAST(net.value AS FLOAT64), bb2.charge_p50)
        * COALESCE(bb2.avg_payer_fraction, 0.78), 2) AS paid_by_payer,
  ROUND(COALESCE(SAFE_CAST(net.value AS FLOAT64), bb2.charge_p50)
        * (1.0 - COALESCE(bb2.avg_payer_fraction, 0.78)), 2) AS paid_by_patient,
  ROUND(COALESCE(SAFE_CAST(net.value AS FLOAT64), bb2.charge_p50)
        * COALESCE(bb2.avg_copay_fraction, 0.0), 2) AS paid_patient_copay,
  ROUND(COALESCE(SAFE_CAST(net.value AS FLOAT64), bb2.charge_p50)
        * COALESCE(bb2.avg_coinsurance_fraction, 0.0), 2) AS paid_patient_coinsurance,
  ROUND(COALESCE(SAFE_CAST(net.value AS FLOAT64), bb2.charge_p50)
        * COALESCE(bb2.avg_deductible_fraction, 0.0), 2) AS paid_patient_deductible,
  ROUND(COALESCE(SAFE_CAST(net.value AS FLOAT64), bb2.charge_p50)
        * COALESCE(bb2.avg_payer_fraction, 0.78), 2) AS paid_by_primary,
  CAST(NULL AS FLOAT64) AS paid_ingredient_cost,
  CAST(NULL AS FLOAT64) AS paid_dispensing_fee,

  ppp.payer_plan_period_id,
  0 AS revenue_code_concept_id,
  0 AS drg_concept_id,
  CAST(NULL AS STRING) AS drg_source_value,
  c.claim_type,
  c.payer_name,
  SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.effective_date, 1, 10)) AS cost_date,
  c.patient_id AS person_source_value,
  CONCAT(c.resource_id, '-', item.sequence) AS cost_source_value,
  c.encounter_id AS encounter_source_value,
  prod.code AS item_procedure_code,
  prod.display AS item_procedure_name,
  prod.system AS item_code_system

FROM `{project}.{dataset}.claim` c

-- Forge sub-tables: claim line items
JOIN `{project}.fhir_normalized_claim.frg__root__raw_1__item1` item
  ON item.ingestion_hash = c.ingestion_hash
LEFT JOIN `{project}.fhir_normalized_claim.frg__root__raw_1__item1__net1` net
  ON net.ingestion_hash = item.ingestion_hash
  AND SPLIT(net.idx, '_')[SAFE_OFFSET(0)] = SPLIT(item.idx, '_')[SAFE_OFFSET(0)]
  AND SPLIT(net.idx, '_')[SAFE_OFFSET(1)] = SPLIT(item.idx, '_')[SAFE_OFFSET(1)]
  AND SPLIT(net.idx, '_')[SAFE_OFFSET(2)] = SPLIT(item.idx, '_')[SAFE_OFFSET(2)]
  AND SPLIT(net.idx, '_')[SAFE_OFFSET(3)] = SPLIT(item.idx, '_')[SAFE_OFFSET(3)]
LEFT JOIN `{project}.fhir_normalized_claim.frg__root__raw_1__item1__prod1__codi1` prod
  ON prod.ingestion_hash = item.ingestion_hash
  AND SPLIT(prod.idx, '_')[SAFE_OFFSET(0)] = SPLIT(item.idx, '_')[SAFE_OFFSET(0)]
  AND SPLIT(prod.idx, '_')[SAFE_OFFSET(1)] = SPLIT(item.idx, '_')[SAFE_OFFSET(1)]
  AND SPLIT(prod.idx, '_')[SAFE_OFFSET(2)] = SPLIT(item.idx, '_')[SAFE_OFFSET(2)]
  AND SPLIT(prod.idx, '_')[SAFE_OFFSET(3)] = SPLIT(item.idx, '_')[SAFE_OFFSET(3)]

-- BB2 Medicare cost calibration (static lookup table)
LEFT JOIN `{project}.{dataset}.bb2_cost_reference` bb2
  ON bb2.claim_type = CASE
    WHEN UPPER(c.claim_type) IN ('INPATIENT','OUTPATIENT','URGENTCARE','SNF','HOME','HOSPICE','HHA')
      THEN 'institutional'
    WHEN UPPER(c.claim_type) IN ('WELLNESS','AMBULATORY')
      THEN 'professional'
    WHEN UPPER(c.claim_type) = 'PRESCRIPTION'
      THEN 'pharmacy'
    ELSE 'professional'
  END

-- Payer plan period FK
LEFT JOIN `{project}.{dataset}.omop_payer_plan_period` ppp
  ON ppp.person_id = ABS(FARM_FINGERPRINT(c.patient_id))
  AND ppp.payer_source_value = c.payer_name

WHERE c.encounter_id IS NOT NULL
  AND SAFE_CAST(net.value AS FLOAT64) > 0
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY c.encounter_id, prod.code
  ORDER BY SAFE_CAST(net.value AS FLOAT64) DESC
) = 1;
