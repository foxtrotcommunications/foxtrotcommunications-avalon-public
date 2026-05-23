{{ config(materialized='table') }}

-- OMOP CDM 5.4 — CONDITION_ERA
-- Derived from condition_occurrence using the standard OHDSI
-- 30-day persistence window algorithm.
--
-- Algorithm:
--   1. Order condition occurrences by person + concept + start_date
--   2. If gap between end of one occurrence and start of next ≤ 30 days,
--      they belong to the same era
--   3. Collapse into continuous eras with min start and max end

WITH conditions_with_end AS (
  SELECT
    person_id,
    condition_concept_id,
    condition_start_date,
    -- If no end date, assume single-day occurrence
    COALESCE(condition_end_date, condition_start_date) AS condition_end_date
  FROM {{ ref('omop_condition_occurrence') }}
  WHERE condition_concept_id IS NOT NULL
    AND condition_concept_id != 0
    AND condition_start_date IS NOT NULL
),

-- Calculate gap from previous occurrence end to current start
-- If gap > 30 days, start a new era (flag = 1)
with_era_flag AS (
  SELECT
    *,
    CASE
      WHEN DATE_DIFF(
        condition_start_date,
        LAG(condition_end_date) OVER (
          PARTITION BY person_id, condition_concept_id
          ORDER BY condition_start_date
        ),
        DAY
      ) > 30
      THEN 1
      ELSE 0
    END AS new_era_flag
  FROM conditions_with_end
),

-- Assign era group by cumulative sum of new_era_flag
with_era_group AS (
  SELECT
    *,
    SUM(new_era_flag) OVER (
      PARTITION BY person_id, condition_concept_id
      ORDER BY condition_start_date
      ROWS UNBOUNDED PRECEDING
    ) AS era_group
  FROM with_era_flag
)

SELECT
  ROW_NUMBER() OVER (ORDER BY person_id, condition_concept_id, MIN(condition_start_date))
    AS condition_era_id,
  person_id,
  condition_concept_id,
  MIN(condition_start_date) AS condition_era_start_date,
  MAX(condition_end_date) AS condition_era_end_date,
  COUNT(*) AS condition_occurrence_count
FROM with_era_group
GROUP BY person_id, condition_concept_id, era_group
