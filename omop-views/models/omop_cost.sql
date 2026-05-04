{{ config(materialized='table') }}

-- OMOP CDM 5.4 — COST
-- Maps forge-core ExplanationOfBenefit item-level adjudication → OMOP cost
-- Adjudication categories pivoted from CMS BlueButton codes:
--   line_sbmtd_chrg_amt     → total_charge
--   line_alowd_chrg_amt     → amount_allowed
--   line_prvdr_pmt_amt      → total_paid / paid_by_payer
--   line_coinsrnc_amt       → paid_patient_coinsurance
--   line_bene_ptb_ddctbl_amt → paid_patient_deductible

-- Resolve the single encounter per EOB. Item-level encounter refs only exist
-- on clinical items (not the administrative items that carry adjudication amounts),
-- so we grab the first non-null encounter reference per EOB (ingestion_hash).
WITH eob_encounter AS (
  SELECT
    item_enc.ingestion_hash,
    REPLACE(
      MIN(item_enc.reference),   -- one encounter per EOB, MIN picks the non-null
      'urn:uuid:', ''
    ) AS encounter_id
  FROM {{ source('forge_eob', 'eob_item_encounter') }} item_enc
  WHERE item_enc.reference IS NOT NULL
    AND item_enc.reference != ''
  GROUP BY item_enc.ingestion_hash
),

eob_adjudication AS (
  SELECT
    r.ingestion_hash,
    r.ingestion_timestamp,
    REPLACE(COALESCE(pat.reference, ''), 'urn:uuid:', '') AS patient_id,
    COALESCE(eob_enc.encounter_id, '') AS encounter_id,
    cat_c.code AS adjudication_category,
    SAFE_CAST(adj_amt.value AS FLOAT64) AS adjudication_amount

  FROM {{ source('forge_eob', 'frg__root') }} r

  {{ forge_join('raw',       'forge_eob', 'eob_raw',                  'r',     2) }}
  {{ forge_join('pat',       'forge_eob', 'eob_patient',              'raw',   3) }}
  {{ forge_join('item',      'forge_eob', 'eob_item',                 'raw',   3) }}
  {{ forge_join('adj',       'forge_eob', 'eob_item_adjudication',    'item',  4) }}
  {{ forge_join('adj_amt',   'forge_eob', 'eob_item_adj_amount',      'adj',   5) }}
  {{ forge_join('cat_c',     'forge_eob', 'eob_item_adj_category_coding', 'adj', 5) }}
  LEFT JOIN eob_encounter eob_enc
    ON eob_enc.ingestion_hash = r.ingestion_hash

  WHERE adj_amt.value IS NOT NULL
),

pivoted AS (
  SELECT
    ingestion_hash,
    encounter_id,
    patient_id,
    MAX(CASE WHEN adjudication_category LIKE '%line_sbmtd_chrg_amt%' THEN adjudication_amount END) AS total_charge,
    MAX(CASE WHEN adjudication_category LIKE '%line_alowd_chrg_amt%' THEN adjudication_amount END) AS amount_allowed,
    MAX(CASE WHEN adjudication_category LIKE '%line_prvdr_pmt_amt%' THEN adjudication_amount END) AS total_paid,
    MAX(CASE WHEN adjudication_category LIKE '%line_coinsrnc_amt%' THEN adjudication_amount END) AS paid_patient_coinsurance,
    MAX(CASE WHEN adjudication_category LIKE '%line_bene_ptb_ddctbl_amt%' THEN adjudication_amount END) AS paid_patient_deductible
  FROM eob_adjudication
  GROUP BY ingestion_hash, encounter_id, patient_id
)

SELECT
  ROW_NUMBER() OVER (ORDER BY p.ingestion_hash, p.encounter_id) AS cost_id,
  ABS(FARM_FINGERPRINT(p.encounter_id)) AS cost_event_id,
  'Visit' AS cost_domain_id,
  31968 AS cost_type_concept_id,
  44818668 AS currency_concept_id,
  p.total_charge,
  p.total_paid,
  p.total_paid AS paid_by_payer,
  COALESCE(p.paid_patient_coinsurance, 0) + COALESCE(p.paid_patient_deductible, 0) AS paid_by_patient,
  CAST(NULL AS FLOAT64) AS paid_patient_copay,  -- not in CMS BlueButton adjudication
  p.paid_patient_coinsurance,
  p.paid_patient_deductible,
  CAST(NULL AS FLOAT64) AS paid_by_primary,
  CAST(NULL AS FLOAT64) AS paid_ingredient_cost,
  CAST(NULL AS FLOAT64) AS paid_dispensing_fee,
  CAST(NULL AS INT64) AS payer_plan_period_id,
  p.amount_allowed,
  0 AS revenue_code_concept_id,
  CAST(NULL AS STRING) AS revenue_code_source_value,
  0 AS drg_concept_id,
  CAST(NULL AS STRING) AS drg_source_value

FROM pivoted p
WHERE p.total_charge IS NOT NULL
   OR p.total_paid IS NOT NULL
