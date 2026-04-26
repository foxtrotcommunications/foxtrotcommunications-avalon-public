-- omop_death — OMOP CDM 5.4
-- Source: FHIR Patient (deceased) + Condition
-- Placeholders: {project}, {dataset}

CREATE OR REPLACE VIEW `{project}.{dataset}.omop_death` AS
WITH deceased AS (
  SELECT patient_id,
    SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(deceased_date_time, 1, 10)) AS death_date,
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%S%Ez', deceased_date_time) AS death_datetime
  FROM `{project}.{dataset}.patient`
  WHERE deceased_date_time IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY ingestion_timestamp DESC) = 1
),
cod AS (
  SELECT c.patient_id, c.code AS cause_snomed_code, c.code_display AS cause_display,
    ROW_NUMBER() OVER (PARTITION BY c.patient_id ORDER BY
      CASE WHEN c.code_display LIKE '%disorder%' THEN 0
           WHEN c.code_display LIKE '%infarction%' THEN 0
           WHEN c.code_display LIKE '%carcinoma%' THEN 0
           WHEN c.code_display LIKE '%hospice%' THEN 1 ELSE 2 END,
      c.effective_date DESC) AS rn
  FROM deceased d JOIN `{project}.{dataset}.condition` c
    ON c.patient_id = d.patient_id AND SUBSTR(c.effective_date, 1, 10) = CAST(d.death_date AS STRING)
)
SELECT ABS(FARM_FINGERPRINT(dp.patient_id)) AS person_id,
  dp.death_date, dp.death_datetime,
  32510 AS death_type_concept_id,
  0 AS cause_concept_id,
  cod.cause_display AS cause_source_value,
  0 AS cause_source_concept_id
FROM deceased dp LEFT JOIN cod ON dp.patient_id = cod.patient_id AND cod.rn = 1;
