{{ config(materialized='table') }}

-- ECCDM Entity: CancerTreatment
-- Interventions administered to treat a cancer condition.
-- Categories: surgery, radiotherapy, systemic (chemo/immuno/hormonal)
-- Uses concept_ancestor hierarchy for cancer-related procedures and drugs.
-- Depends on: omop_procedure_occurrence, omop_drug_exposure, eccdm_cancer_patient

-- Surgery — procedures classified under surgical concepts
SELECT
  po.procedure_occurrence_id                        AS treatment_id,
  'procedure_occurrence'                            AS source_table,
  po.person_id,
  po.procedure_concept_id                           AS treatment_concept_id,
  c.concept_name                                    AS treatment_name,
  po.procedure_source_value                         AS treatment_code,
  'surgery'                                         AS treatment_category,
  po.procedure_date                                 AS treatment_start_date,
  CAST(NULL AS DATE)                                AS treatment_end_date,
  po.visit_occurrence_id,
  po.provider_id
FROM {{ ref('omop_procedure_occurrence') }} po
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = po.person_id
JOIN {{ source('omop_vocab', 'concept') }} c
  ON c.concept_id = po.procedure_concept_id
WHERE po.procedure_concept_id IN (
  SELECT ca.descendant_concept_id
  FROM {{ source('omop_vocab', 'concept_ancestor') }} ca
  WHERE ca.ancestor_concept_id IN (
    4301351,   -- Surgical procedure (broad)
    4180572    -- Excision
  )
)
AND po.procedure_concept_id NOT IN (
  -- Exclude non-cancer-specific surgeries by checking if concept name
  -- suggests dental, routine, or screening procedures
  SELECT ca.descendant_concept_id
  FROM {{ source('omop_vocab', 'concept_ancestor') }} ca
  WHERE ca.ancestor_concept_id IN (
    4322471    -- Dental procedure
  )
)

UNION ALL

-- Radiotherapy and combined chemo/radiation
SELECT
  po.procedure_occurrence_id                        AS treatment_id,
  'procedure_occurrence'                            AS source_table,
  po.person_id,
  po.procedure_concept_id                           AS treatment_concept_id,
  c.concept_name                                    AS treatment_name,
  po.procedure_source_value                         AS treatment_code,
  'radiotherapy'                                    AS treatment_category,
  po.procedure_date                                 AS treatment_start_date,
  CAST(NULL AS DATE)                                AS treatment_end_date,
  po.visit_occurrence_id,
  po.provider_id
FROM {{ ref('omop_procedure_occurrence') }} po
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = po.person_id
JOIN {{ source('omop_vocab', 'concept') }} c
  ON c.concept_id = po.procedure_concept_id
WHERE (
  po.procedure_concept_id IN (
    SELECT ca.descendant_concept_id
    FROM {{ source('omop_vocab', 'concept_ancestor') }} ca
    WHERE ca.ancestor_concept_id IN (
      4029715,   -- Radiation therapy
      4215685    -- Radiotherapy
    )
  )
  -- Also match the specific Synthea chemo+radiation code
  OR po.procedure_source_value = '703423002'
)

UNION ALL

-- Systemic treatment (chemotherapy, immunotherapy, hormonal)
-- Match cancer patients' drug exposures for known oncology RxNorm concepts
SELECT
  de.drug_exposure_id                               AS treatment_id,
  'drug_exposure'                                   AS source_table,
  de.person_id,
  de.drug_concept_id                                AS treatment_concept_id,
  c.concept_name                                    AS treatment_name,
  de.drug_source_value                              AS treatment_code,
  'systemic'                                        AS treatment_category,
  de.drug_exposure_start_date                       AS treatment_start_date,
  de.drug_exposure_end_date                         AS treatment_end_date,
  de.visit_occurrence_id,
  de.provider_id
FROM {{ ref('omop_drug_exposure') }} de
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = de.person_id
JOIN {{ source('omop_vocab', 'concept') }} c
  ON c.concept_id = de.drug_concept_id
WHERE de.drug_concept_id IN (
  SELECT ca.descendant_concept_id
  FROM {{ source('omop_vocab', 'concept_ancestor') }} ca
  WHERE ca.ancestor_concept_id IN (
    21601386,   -- Antineoplastic agents (ATC L01)
    21603931,   -- Endocrine therapy (ATC L02)
    21604847    -- Immunostimulants (ATC L03)
  )
)
