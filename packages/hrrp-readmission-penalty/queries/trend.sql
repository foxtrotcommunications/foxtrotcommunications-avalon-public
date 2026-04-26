-- ─────────────────────────────────────────────────────────────────────────────
-- hrrp-readmission-penalty · trend.sql
--
-- Monthly 30-day readmission trend per HRRP condition.
-- Used to power the trend chart tab in the analytics package card.
--
-- Output schema:
--   month              — YYYY-MM string
--   condition          — AMI | HF | PN | COPD | CABG | THA_TKA
--   total_admissions   — index admits in that month
--   total_readmits     — 30-day readmissions
--   readmit_rate       — observed readmission rate (0–1)
--   national_expected  — CMS FY2024 national expected rate (0–1)
--   err                — excess readmission ratio (observed / expected)
--   above_benchmark    — TRUE if err > 1.0
--   rolling_3m_rate    — 3-month rolling average readmission rate
-- ─────────────────────────────────────────────────────────────────────────────

WITH

-- ── Condition grouper (same logic as main.sql) ────────────────────────────────
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

procedure_grouper AS (
  SELECT po.person_id, po.visit_occurrence_id,
    CASE
      WHEN po.procedure_source_value IN (
        '232717009','10326007','67091002','36819002','80762004','3546002','414088005','5486006'
      ) THEN 'CABG'
      WHEN po.procedure_source_value IN (
        '52734007','76915002','265157000','609588000','57533007','179294004','265170009'
      ) THEN 'THA_TKA'
      ELSE NULL
    END AS hrrp_category
  FROM `{project}.{dataset}.omop_procedure_occurrence` po
  WHERE po.visit_occurrence_id IS NOT NULL
),

hrrp_per_visit AS (
  SELECT DISTINCT person_id, visit_occurrence_id, hrrp_category
  FROM (
    SELECT person_id, visit_occurrence_id, hrrp_category,
      ROW_NUMBER() OVER (
        PARTITION BY visit_occurrence_id
        ORDER BY CASE hrrp_category
          WHEN 'AMI' THEN 1 WHEN 'HF' THEN 2 WHEN 'PN' THEN 3
          WHEN 'COPD' THEN 4 WHEN 'CABG' THEN 5 WHEN 'THA_TKA' THEN 6
        END
      ) AS rn
    FROM (
      SELECT person_id, visit_occurrence_id, hrrp_category FROM condition_grouper WHERE hrrp_category IS NOT NULL
      UNION ALL
      SELECT person_id, visit_occurrence_id, hrrp_category FROM procedure_grouper WHERE hrrp_category IS NOT NULL
    )
  )
  WHERE rn = 1
),

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

-- ── Index admissions ──────────────────────────────────────────────────────────
index_admissions AS (
  SELECT
    v.person_id, v.visit_occurrence_id,
    v.visit_start_date, v.visit_end_date,
    hg.hrrp_category
  FROM `{project}.{dataset}.omop_visit_occurrence` v
  INNER JOIN hrrp_per_visit hg USING (visit_occurrence_id)
  WHERE v.visit_concept_id IN (9201, 262, 9203)
    AND v.visit_end_date IS NOT NULL
    AND v.visit_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {lookback_months} MONTH)
    AND v.visit_start_date < DATE_TRUNC(CURRENT_DATE(), MONTH)  -- exclude current incomplete month
),

-- ── 30-day readmissions ───────────────────────────────────────────────────────
readmissions AS (
  SELECT
    idx.visit_occurrence_id, idx.hrrp_category,
    idx.visit_start_date,
    CASE WHEN COUNT(ra.visit_occurrence_id) > 0 THEN 1 ELSE 0 END AS readmitted
  FROM index_admissions idx
  LEFT JOIN `{project}.{dataset}.omop_visit_occurrence` ra
    ON  ra.person_id          = idx.person_id
    AND ra.visit_start_date   > idx.visit_end_date
    AND ra.visit_start_date  <= DATE_ADD(idx.visit_end_date, INTERVAL 30 DAY)
    AND ra.visit_concept_id   IN (9201, 262, 9203)
    AND ra.visit_occurrence_id != idx.visit_occurrence_id
  GROUP BY 1, 2, 3
),

-- ── Monthly aggregation ───────────────────────────────────────────────────────
monthly AS (
  SELECT
    FORMAT_DATE('%Y-%m', DATE_TRUNC(r.visit_start_date, MONTH)) AS month,
    DATE_TRUNC(r.visit_start_date, MONTH)                        AS month_date,
    r.hrrp_category                                              AS condition,
    nb.expected_rate                                             AS national_expected,
    COUNT(*)                                                      AS total_admissions,
    SUM(r.readmitted)                                            AS total_readmits,
    SAFE_DIVIDE(SUM(r.readmitted), COUNT(*))                     AS readmit_rate
  FROM readmissions r
  JOIN national_benchmarks nb ON nb.condition = r.hrrp_category
  GROUP BY 1, 2, 3, 4
)

-- ── Final output with rolling average ────────────────────────────────────────
SELECT
  month,
  condition,
  total_admissions,
  total_readmits,
  ROUND(readmit_rate, 4)           AS readmit_rate,
  ROUND(national_expected, 4)      AS national_expected,
  ROUND(SAFE_DIVIDE(readmit_rate, national_expected), 3) AS err,
  readmit_rate > national_expected AS above_benchmark,
  -- 3-month rolling average readmission rate
  ROUND(AVG(readmit_rate) OVER (
    PARTITION BY condition
    ORDER BY month_date
    ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
  ), 4)                            AS rolling_3m_rate
FROM monthly
ORDER BY condition, month
