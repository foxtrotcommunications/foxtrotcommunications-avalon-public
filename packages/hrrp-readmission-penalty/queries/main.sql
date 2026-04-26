-- ─────────────────────────────────────────────────────────────────────────────
-- hrrp-readmission-penalty · main.sql  (v1.1 — all 6 CMS conditions)
--
-- CMS HRRP Readmission Penalty Scorecard — condition-level output.
-- Covers all six HRRP conditions:
--   Condition-based : AMI, Heart Failure, Pneumonia, COPD
--   Procedure-based : CABG, THA/TKA
--
-- Injected by Anvil at execution time:
--   {project}            — GCP project ID
--   {dataset}            — OMOP dataset (e.g. forge_synthetic_fhir)
--   {lookback_months}    — integer, default 24
--   {scenario}           — 'baseline' | 'high_risk'
--   {ami_target_rate}    — float, high_risk scenario AMI target
--   {hf_target_rate}     — float, high_risk scenario HF target
--   {pn_target_rate}     — float, high_risk scenario PN target
--   {copd_target_rate}   — float, high_risk scenario COPD target
--   {cabg_target_rate}   — float, high_risk scenario CABG target
--   {tha_tka_target_rate}— float, high_risk scenario THA/TKA target
--
-- Output schema (scorecard):
--   condition, total_admissions, total_readmits, real_readmits,
--   synthetic_readmits, observed_readmit_pct, national_expected_pct,
--   excess_readmit_ratio, hrrp_status, avg_los_days,
--   avg_index_cost, avg_readmit_cost, avg_patient_oop,
--   base_payments, total_readmit_impact, simulated_hrrp_penalty
-- ─────────────────────────────────────────────────────────────────────────────

WITH

-- ── Condition-based HRRP grouper (AMI / HF / PN / COPD) ──────────────────────
-- Uses SNOMED source values as coded in Synthea / standard OMOP pipelines.
condition_grouper AS (
  SELECT co.person_id, co.visit_occurrence_id,
    CASE
      WHEN co.condition_source_value IN (
        '57054005','22298006','70422006','307140009','401303003','401314000',
        '194802006','55234003','233825009','413444003'
      ) THEN 'AMI'
      WHEN co.condition_source_value IN (
        '84114007','42343007','48447003','417996009','441530006','56675007','5148006',
        '367363000','73595000','194767001','46221000','44313002'
      ) THEN 'HF'
      WHEN co.condition_source_value IN (
        '233604007','53084003','233616003','278516003','195900001',
        '87512008','882784691000119100','363746003','75570004'
      ) THEN 'PN'
      WHEN co.condition_source_value IN (
        '13645005','185086009','87433001','195967001','10567002',
        '313299006','67811000119102'
      ) THEN 'COPD'
      ELSE NULL
    END AS hrrp_category
  FROM `{project}.{dataset}.omop_condition_occurrence` co
  WHERE co.visit_occurrence_id IS NOT NULL
),

-- ── Procedure-based HRRP grouper (CABG / THA / TKA) ─────────────────────────
-- Joins to omop_procedure_occurrence on the same visit.
-- SNOMED codes cover standard Synthea surgical procedure encoding.
procedure_grouper AS (
  SELECT po.person_id, po.visit_occurrence_id,
    CASE
      WHEN po.procedure_source_value IN (
        -- CABG variants (Synthea SNOMED)
        '232717009',   -- CABG x4
        '10326007',    -- CABG using arterial graft
        '67091002',    -- CABG
        '36819002',    -- CABG x2
        '80762004',    -- CABG using saphenous vein
        '3546002',     -- Aortocoro bypass (internal mammary)
        '414088005',   -- Emergency CABG
        '5486006'      -- Delayed CABG
      ) THEN 'CABG'
      WHEN po.procedure_source_value IN (
        -- Total Hip Arthroplasty
        '52734007',    -- Total hip replacement
        '76915002',    -- Total hip replacement with prosthesis
        '265157000'    -- Hip arthroplasty
      ) THEN 'THA_TKA'
      WHEN po.procedure_source_value IN (
        -- Total Knee Arthroplasty
        '609588000',   -- Total knee replacement
        '57533007',    -- Knee arthroplasty
        '179294004',   -- Total condylar knee replacement
        '265170009'    -- Revision of knee replacement
      ) THEN 'THA_TKA'
      ELSE NULL
    END AS hrrp_category
  FROM `{project}.{dataset}.omop_procedure_occurrence` po
  WHERE po.visit_occurrence_id IS NOT NULL
),

-- ── Unified grouper — merge condition + procedure groupers ────────────────────
hrrp_grouper AS (
  SELECT person_id, visit_occurrence_id, hrrp_category FROM condition_grouper WHERE hrrp_category IS NOT NULL
  UNION ALL
  SELECT person_id, visit_occurrence_id, hrrp_category FROM procedure_grouper WHERE hrrp_category IS NOT NULL
),

-- ── Deduplicate (one HRRP category per visit, prefer condition-based) ─────────
hrrp_per_visit AS (
  SELECT DISTINCT person_id, visit_occurrence_id, hrrp_category
  FROM (
    SELECT person_id, visit_occurrence_id, hrrp_category,
      ROW_NUMBER() OVER (
        PARTITION BY visit_occurrence_id
        ORDER BY CASE hrrp_category
          WHEN 'AMI'     THEN 1   -- Most severe first (prioritise acute)
          WHEN 'HF'      THEN 2
          WHEN 'PN'      THEN 3
          WHEN 'COPD'    THEN 4
          WHEN 'CABG'    THEN 5
          WHEN 'THA_TKA' THEN 6
        END
      ) AS rn
    FROM hrrp_grouper
  )
  WHERE rn = 1
),

-- ── CMS national benchmarks (FY2024) ─────────────────────────────────────────
national_benchmarks AS (
  SELECT * FROM UNNEST([
    STRUCT('AMI'     AS condition, 0.165  AS expected_rate),
    STRUCT('HF'      AS condition, 0.215  AS expected_rate),
    STRUCT('PN'      AS condition, 0.150  AS expected_rate),
    STRUCT('COPD'    AS condition, 0.198  AS expected_rate),
    STRUCT('CABG'    AS condition, 0.1255 AS expected_rate),
    STRUCT('THA_TKA' AS condition, 0.045  AS expected_rate)
  ])
),

-- ── Index admissions (inpatient stays with an HRRP diagnosis/procedure) ───────
index_admissions AS (
  SELECT
    v.person_id, v.visit_occurrence_id,
    v.visit_start_date AS admit_date,
    v.visit_end_date   AS discharge_date,
    DATE_DIFF(v.visit_end_date, v.visit_start_date, DAY) AS los_days,
    hg.hrrp_category,
    COALESCE(SUM(c.total_paid),   0) AS index_cost,
    COALESCE(SUM(c.total_charge), 0) AS index_charged,
    COALESCE(SUM(
      c.paid_patient_copay + c.paid_patient_deductible + c.paid_patient_coinsurance
    ), 0) AS patient_oop
  FROM `{project}.{dataset}.omop_visit_occurrence` v
  INNER JOIN hrrp_per_visit hg USING (visit_occurrence_id)
  LEFT JOIN `{project}.{dataset}.omop_cost` c
    ON c.cost_event_id = v.visit_occurrence_id
  WHERE v.visit_concept_id IN (
    9201,   -- Inpatient
    262,    -- ER→Inpatient
    9203    -- Emergency Room
  )
    AND v.visit_end_date IS NOT NULL
    AND v.visit_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {lookback_months} MONTH)
  GROUP BY 1,2,3,4,5,6
),

-- ── 30-day readmissions ───────────────────────────────────────────────────────
real_readmissions AS (
  SELECT
    idx.person_id,
    idx.visit_occurrence_id AS index_visit_id,
    idx.hrrp_category,
    idx.admit_date, idx.discharge_date, idx.los_days,
    idx.index_cost, idx.patient_oop,
    MIN(ra.visit_occurrence_id) AS readmit_visit_id,
    CASE WHEN COUNT(ra.visit_occurrence_id) > 0 THEN TRUE ELSE FALSE END AS readmitted
  FROM index_admissions idx
  LEFT JOIN `{project}.{dataset}.omop_visit_occurrence` ra
    ON  ra.person_id          = idx.person_id
    AND ra.visit_start_date   > idx.discharge_date
    AND ra.visit_start_date  <= DATE_ADD(idx.discharge_date, INTERVAL 30 DAY)
    AND ra.visit_concept_id   IN (9201, 262, 9203)
    AND ra.visit_occurrence_id != idx.visit_occurrence_id
  GROUP BY 1,2,3,4,5,6,7,8
),

-- ── Readmission costs ────────────────────────────────────────────────────────
readmission_costs AS (
  SELECT r.index_visit_id,
    COALESCE(SUM(c.total_paid), 0) AS readmit_cost
  FROM real_readmissions r
  JOIN `{project}.{dataset}.omop_cost` c ON c.cost_event_id = r.readmit_visit_id
  WHERE r.readmit_visit_id IS NOT NULL
  GROUP BY 1
),

-- ── Synthetic overlay (scenario = 'high_risk' only) ──────────────────────────
-- Deterministically promotes a subset of non-readmitted stays to readmitted
-- status to demonstrate penalty exposure above CMS national benchmarks.
synthetic_readmissions AS (
  SELECT
    index_visit_id, hrrp_category,
    ROUND(index_cost * 0.65, 0) AS synthetic_readmit_cost
  FROM (
    SELECT
      index_visit_id, hrrp_category, index_cost,
      ROW_NUMBER() OVER (
        PARTITION BY hrrp_category
        ORDER BY ABS(FARM_FINGERPRINT(CAST(index_visit_id AS STRING)))
      ) AS rn,
      COUNT(*) OVER (PARTITION BY hrrp_category)           AS total_in_cat,
      COUNTIF(readmitted) OVER (PARTITION BY hrrp_category) AS already_readmitted,
      CASE hrrp_category
        WHEN 'AMI'     THEN {ami_target_rate}
        WHEN 'HF'      THEN {hf_target_rate}
        WHEN 'PN'      THEN {pn_target_rate}
        WHEN 'COPD'    THEN {copd_target_rate}
        WHEN 'CABG'    THEN {cabg_target_rate}
        WHEN 'THA_TKA' THEN {tha_tka_target_rate}
      END AS target_rate
    FROM real_readmissions
    WHERE NOT readmitted
  )
  WHERE '{scenario}' = 'high_risk'
    AND rn <= GREATEST(0,
      CAST(ROUND(target_rate * total_in_cat) - already_readmitted AS INT64)
    )
),

-- ── Merged view ───────────────────────────────────────────────────────────────
all_readmissions AS (
  SELECT
    r.person_id, r.index_visit_id, r.hrrp_category,
    r.admit_date, r.discharge_date, r.los_days,
    r.index_cost, r.patient_oop,
    r.readmitted                         AS real_readmit,
    s.index_visit_id IS NOT NULL         AS synthetic_readmit,
    (r.readmitted OR s.index_visit_id IS NOT NULL) AS readmitted_final,
    CASE
      WHEN r.readmitted              THEN COALESCE(rc.readmit_cost, 0)
      WHEN s.index_visit_id IS NOT NULL THEN s.synthetic_readmit_cost
      ELSE 0
    END AS readmit_cost
  FROM real_readmissions r
  LEFT JOIN readmission_costs    rc USING (index_visit_id)
  LEFT JOIN synthetic_readmissions s USING (index_visit_id)
),

-- ── Scorecard aggregation ─────────────────────────────────────────────────────
scorecard AS (
  SELECT
    a.hrrp_category,
    nb.expected_rate                         AS national_expected_rate,
    COUNT(*)                                  AS total_admissions,
    COUNTIF(real_readmit)                     AS real_readmits,
    COUNTIF(synthetic_readmit)                AS synthetic_readmits,
    COUNTIF(readmitted_final)                 AS total_readmits,
    SAFE_DIVIDE(COUNTIF(readmitted_final), COUNT(*)) AS observed_rate,
    ROUND(AVG(los_days), 1)                  AS avg_los,
    ROUND(AVG(index_cost), 0)                AS avg_index_cost,
    ROUND(AVG(IF(readmitted_final, readmit_cost, NULL)), 0) AS avg_readmit_cost,
    ROUND(SUM(index_cost), 0)                AS base_payments,
    ROUND(SUM(readmit_cost), 0)              AS total_readmit_impact,
    ROUND(AVG(patient_oop), 0)               AS avg_patient_oop
  FROM all_readmissions a
  JOIN national_benchmarks nb ON nb.condition = a.hrrp_category
  GROUP BY 1, 2
)

-- ── Final output ──────────────────────────────────────────────────────────────
-- Always output all 6 HRRP conditions. Conditions with no qualifying admissions
-- in the lookback window show zeros and a 'NO_DATA' status.
SELECT
  nb.condition                                           AS condition,
  COALESCE(s.total_admissions, 0)                        AS total_admissions,
  COALESCE(s.total_readmits, 0)                          AS total_readmits,
  COALESCE(s.real_readmits, 0)                           AS real_readmits,
  COALESCE(s.synthetic_readmits, 0)                      AS synthetic_readmits,
  ROUND(COALESCE(s.observed_rate, 0) * 100, 1)           AS observed_readmit_pct,
  ROUND(nb.expected_rate * 100, 1)                       AS national_expected_pct,
  ROUND(SAFE_DIVIDE(s.observed_rate, nb.expected_rate), 3) AS excess_readmit_ratio,
  CASE
    WHEN s.total_admissions IS NULL OR s.total_admissions = 0 THEN 'NO_DATA'
    WHEN SAFE_DIVIDE(s.observed_rate, nb.expected_rate) > 1.0 THEN 'PENALTY_EXPOSURE'
    ELSE 'WITHIN_BENCHMARK'
  END                                                    AS hrrp_status,
  COALESCE(s.avg_los, 0)                                 AS avg_los_days,
  COALESCE(s.avg_index_cost, 0)                          AS avg_index_cost,
  s.avg_readmit_cost,
  COALESCE(s.avg_patient_oop, 0)                         AS avg_patient_oop,
  COALESCE(s.base_payments, 0)                           AS base_payments,
  COALESCE(s.total_readmit_impact, 0)                    AS total_readmit_impact,
  COALESCE(ROUND(
    GREATEST(0, SAFE_DIVIDE(s.observed_rate, nb.expected_rate) - 1.0)
    * s.base_payments * 0.03, 0
  ), 0)                                                  AS simulated_hrrp_penalty,
  '{scenario}'                                           AS _scenario,
  CURRENT_TIMESTAMP()                                    AS _executed_at
FROM national_benchmarks nb
LEFT JOIN scorecard s ON s.hrrp_category = nb.condition
ORDER BY simulated_hrrp_penalty DESC, COALESCE(excess_readmit_ratio, 0) DESC

