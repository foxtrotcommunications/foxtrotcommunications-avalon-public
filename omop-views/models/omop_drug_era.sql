{{ config(materialized='table') }}

-- OMOP CDM 5.4 — DRUG_ERA
-- Derived from drug_exposure using the standard OHDSI
-- 30-day persistence window algorithm.
--
-- Algorithm:
--   1. Order drug exposures by person + concept + start_date
--   2. If gap between end of one exposure and start of next ≤ 30 days,
--      they belong to the same era
--   3. Collapse into continuous eras with min start and max end
--
-- Note: OHDSI convention maps drug_concept_id to ingredient level
-- for era computation. In this implementation we use the drug_concept_id
-- directly (which may be ingredient, clinical drug, or brand).
-- TODO: Roll up to ingredient level via concept_ancestor table.

WITH exposures_with_end AS (
  SELECT
    person_id,
    drug_concept_id,
    drug_exposure_start_date,
    -- If no end date, assume 1-day exposure (per OHDSI convention)
    COALESCE(drug_exposure_end_date, drug_exposure_start_date) AS drug_exposure_end_date
  FROM {{ ref('omop_drug_exposure') }}
  WHERE drug_concept_id IS NOT NULL
    AND drug_concept_id != 0
    AND drug_exposure_start_date IS NOT NULL
),

-- Calculate gap from previous exposure end to current start
-- If gap > 30 days, start a new era (flag = 1)
with_era_flag AS (
  SELECT
    *,
    CASE
      WHEN DATE_DIFF(
        drug_exposure_start_date,
        LAG(drug_exposure_end_date) OVER (
          PARTITION BY person_id, drug_concept_id
          ORDER BY drug_exposure_start_date
        ),
        DAY
      ) > 30
      THEN 1
      ELSE 0
    END AS new_era_flag
  FROM exposures_with_end
),

-- Assign era group by cumulative sum of new_era_flag
with_era_group AS (
  SELECT
    *,
    SUM(new_era_flag) OVER (
      PARTITION BY person_id, drug_concept_id
      ORDER BY drug_exposure_start_date
      ROWS UNBOUNDED PRECEDING
    ) AS era_group
  FROM with_era_flag
)

SELECT
  ROW_NUMBER() OVER (ORDER BY person_id, drug_concept_id, MIN(drug_exposure_start_date))
    AS drug_era_id,
  person_id,
  drug_concept_id,
  MIN(drug_exposure_start_date) AS drug_era_start_date,
  MAX(drug_exposure_end_date) AS drug_era_end_date,
  COUNT(*) AS drug_exposure_count,
  -- Gap days: total gap days within the era (days between exposures)
  GREATEST(
    DATE_DIFF(MAX(drug_exposure_end_date), MIN(drug_exposure_start_date), DAY)
    - SUM(DATE_DIFF(drug_exposure_end_date, drug_exposure_start_date, DAY)),
    0
  ) AS gap_days
FROM with_era_group
GROUP BY person_id, drug_concept_id, era_group
