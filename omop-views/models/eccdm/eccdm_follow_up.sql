{{ config(materialized='view') }}

-- ECCDM Entity: LastFollowUp
-- Most recent follow-up information for each cancer patient.
-- Summary of the latest known clinical status.
-- Depends on: omop_visit_occurrence, omop_death, eccdm_cancer_patient, eccdm_cancer_condition

WITH latest_visit AS (
  SELECT
    vo.person_id,
    vo.visit_occurrence_id,
    vo.visit_start_date                             AS follow_up_date,
    vo.visit_concept_id,
    ROW_NUMBER() OVER (
      PARTITION BY vo.person_id
      ORDER BY vo.visit_start_date DESC
    )                                               AS rn
  FROM {{ ref('omop_visit_occurrence') }} vo
  INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
    ON cp.person_id = vo.person_id
),

first_diagnosis AS (
  SELECT
    person_id,
    MIN(diagnosis_date) AS diagnosis_date
  FROM {{ ref('eccdm_cancer_condition') }}
  GROUP BY person_id
),

last_treatment AS (
  SELECT
    person_id,
    MAX(treatment_start_date) AS last_treatment_date
  FROM {{ ref('eccdm_cancer_treatment') }}
  GROUP BY person_id
)

SELECT
  lv.person_id,
  lv.visit_occurrence_id                            AS last_visit_id,
  lv.follow_up_date,
  lv.visit_concept_id,

  -- Vital status
  CASE
    WHEN cp.is_deceased THEN 'deceased'
    ELSE 'alive'
  END                                               AS vital_status,
  cp.death_date,
  cp.last_observation_date                          AS last_known_date,

  -- Days since diagnosis
  DATE_DIFF(lv.follow_up_date, dx.diagnosis_date, DAY) AS days_since_diagnosis,

  -- Days since last treatment
  DATE_DIFF(lv.follow_up_date, tx.last_treatment_date, DAY) AS days_since_last_treatment

FROM latest_visit lv
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = lv.person_id
LEFT JOIN first_diagnosis dx
  ON dx.person_id = lv.person_id
LEFT JOIN last_treatment tx
  ON tx.person_id = lv.person_id
WHERE lv.rn = 1
