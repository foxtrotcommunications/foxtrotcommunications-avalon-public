{{ config(materialized='table') }}

-- OMOP CDM 5.4 — DEATH
-- Infers cause of death from same-day condition records

WITH deceased AS (
  SELECT
    patient_id,
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(deceased_date_time, 1, 10)) AS death_date,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S%Ez', deceased_date_time) AS death_datetime
  FROM {{ ref('stg_patient') }}
  WHERE deceased_date_time IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY ingestion_timestamp DESC) = 1
),

cause_of_death AS (
  SELECT
    c.patient_id,
    c.code AS cause_snomed_code,
    c.code_display AS cause_display,
    ROW_NUMBER() OVER (
      PARTITION BY c.patient_id
      ORDER BY
        CASE
          WHEN c.code_display LIKE '%disorder%' THEN 0
          WHEN c.code_display LIKE '%infarction%' THEN 0
          WHEN c.code_display LIKE '%carcinoma%' THEN 0
          WHEN c.code_display LIKE '%hospice%' THEN 1
          ELSE 2
        END,
        c.effective_date DESC
    ) AS rn
  FROM deceased d
  JOIN {{ ref('stg_condition') }} c
    ON c.patient_id = d.patient_id
    AND SUBSTR(c.effective_date, 1, 10) = CAST(d.death_date AS STRING)
)

SELECT
  ABS(FARM_FINGERPRINT(dp.patient_id)) AS person_id,
  dp.death_date,
  dp.death_datetime,
  32510 AS death_type_concept_id,
  {{ resolve_concept('cod.cause_snomed_code', 'SNOMED') }} AS cause_concept_id,
  cod.cause_display AS cause_source_value,
  {{ resolve_source_concept('cod.cause_snomed_code', 'SNOMED') }} AS cause_source_concept_id
FROM deceased dp
LEFT JOIN cause_of_death cod
  ON dp.patient_id = cod.patient_id AND cod.rn = 1
