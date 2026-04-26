-- ─────────────────────────────────────────────────────────────────────────────
-- hrrp-readmission-penalty · detail.sql
-- Patient-level readmission events — drilldown from scorecard
--
-- Injected: {project}, {dataset}, {lookback_months}, {scenario}
-- Output: one row per index admission that resulted in a 30-day readmission
-- ─────────────────────────────────────────────────────────────────────────────

WITH hrrp_grouper AS (
  SELECT co.person_id, co.visit_occurrence_id,
    CASE
      WHEN co.condition_source_value IN (
        '57054005','22298006','70422006','307140009','401303003','401314000') THEN 'AMI'
      WHEN co.condition_source_value IN (
        '84114007','42343007','48447003','417996009','441530006','56675007','5148006') THEN 'HF'
      WHEN co.condition_source_value IN (
        '233604007','53084003','233616003','278516003','195900001') THEN 'PN'
      WHEN co.condition_source_value IN (
        '13645005','185086009','87433001','195967001','10567002') THEN 'COPD'
      ELSE NULL
    END AS hrrp_category
  FROM `{project}.{dataset}.omop_condition_occurrence` co
  WHERE co.visit_occurrence_id IS NOT NULL
),
index_admissions AS (
  SELECT
    v.person_id, v.visit_occurrence_id,
    v.visit_start_date AS admit_date, v.visit_end_date AS discharge_date,
    DATE_DIFF(v.visit_end_date, v.visit_start_date, DAY) AS los_days,
    hg.hrrp_category,
    COALESCE(SUM(c.total_paid), 0)   AS index_cost,
    COALESCE(SUM(c.total_charge), 0) AS index_charged,
    COALESCE(SUM(
      c.paid_patient_copay + c.paid_patient_deductible + c.paid_patient_coinsurance
    ), 0) AS patient_oop
  FROM `{project}.{dataset}.omop_visit_occurrence` v
  INNER JOIN hrrp_grouper hg
    ON hg.visit_occurrence_id = v.visit_occurrence_id AND hg.hrrp_category IS NOT NULL
  LEFT JOIN `{project}.{dataset}.omop_cost` c ON c.cost_event_id = v.visit_occurrence_id
  WHERE v.visit_concept_id IN (9201, 262, 9203)
    AND v.visit_end_date IS NOT NULL
    AND v.visit_start_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {lookback_months} MONTH)
  GROUP BY 1,2,3,4,5,6
),
readmissions AS (
  SELECT
    idx.person_id, idx.visit_occurrence_id AS index_visit_id,
    idx.hrrp_category, idx.admit_date, idx.discharge_date, idx.los_days,
    idx.index_cost, idx.index_charged, idx.patient_oop,
    ra.visit_occurrence_id AS readmit_visit_id,
    ra.visit_start_date    AS readmit_date,
    DATE_DIFF(ra.visit_start_date, idx.discharge_date, DAY) AS days_to_readmit,
    COALESCE(SUM(rc.total_paid), 0) AS readmit_cost
  FROM index_admissions idx
  JOIN `{project}.{dataset}.omop_visit_occurrence` ra
    ON  ra.person_id = idx.person_id
    AND ra.visit_start_date > idx.discharge_date
    AND ra.visit_start_date <= DATE_ADD(idx.discharge_date, INTERVAL 30 DAY)
    AND ra.visit_concept_id IN (9201, 262, 9203)
    AND ra.visit_occurrence_id != idx.visit_occurrence_id
  LEFT JOIN `{project}.{dataset}.omop_cost` rc ON rc.cost_event_id = ra.visit_occurrence_id
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12
  QUALIFY ROW_NUMBER() OVER (PARTITION BY idx.visit_occurrence_id ORDER BY ra.visit_start_date) = 1
)

SELECT
  p.person_source_value            AS patient_ref,
  r.hrrp_category                  AS condition,
  r.admit_date,
  r.discharge_date,
  r.los_days,
  ROUND(r.index_cost, 2)           AS index_cost,
  ROUND(r.index_charged, 2)        AS index_charged,
  ROUND(r.patient_oop, 2)          AS patient_oop,
  r.readmit_date,
  r.days_to_readmit,
  ROUND(r.readmit_cost, 2)         AS readmit_cost,
  ROUND(r.index_cost + r.readmit_cost, 2) AS total_episode_cost,
  FALSE                            AS is_synthetic,
  CURRENT_TIMESTAMP()              AS _executed_at
FROM readmissions r
JOIN `{project}.{dataset}.omop_person` p USING (person_id)
ORDER BY r.index_cost DESC
