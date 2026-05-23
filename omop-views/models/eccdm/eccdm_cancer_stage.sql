{{ config(materialized='view') }}

-- ECCDM Entity: CancerStage
-- Staging assessment (clinical cTNM and pathological pTNM).
-- Depends on: omop_measurement
--
-- Key LOINC codes:
--   21908-9  Stage group.clinical
--   21902-2  Stage group.pathological
--   21905-5  T (clinical)
--   21906-3  N (clinical)
--   21907-1  M (clinical)
--   21899-0  pT (pathological)
--   21900-6  pN (pathological)
--   21901-4  pM (pathological)

SELECT
  m.measurement_id,
  m.person_id,
  m.measurement_concept_id,
  m.measurement_source_value                        AS loinc_code,
  m.value_as_number,
  m.value_as_concept_id,
  m.value_source_value                              AS stage_value,
  m.measurement_date                                AS staging_date,
  m.measurement_datetime                            AS staging_datetime,
  m.measurement_source_concept_id,
  m.visit_occurrence_id,

  -- Classify as clinical or pathological
  CASE
    WHEN m.measurement_source_value IN ('21908-9', '21905-5', '21906-3', '21907-1')
      THEN 'clinical'
    WHEN m.measurement_source_value IN ('21902-2', '21899-0', '21900-6', '21901-4')
      THEN 'pathological'
    ELSE 'unknown'
  END                                               AS staging_type,

  -- Classify TNM component
  CASE
    WHEN m.measurement_source_value IN ('21908-9', '21902-2') THEN 'stage_group'
    WHEN m.measurement_source_value IN ('21905-5', '21899-0') THEN 'T'
    WHEN m.measurement_source_value IN ('21906-3', '21900-6') THEN 'N'
    WHEN m.measurement_source_value IN ('21907-1', '21901-4') THEN 'M'
    ELSE 'other'
  END                                               AS tnm_component

FROM {{ ref('omop_measurement') }} m
WHERE m.measurement_source_value IN (
  '21908-9', '21902-2',
  '21905-5', '21899-0',
  '21906-3', '21900-6',
  '21907-1', '21901-4'
)
