{{ config(materialized='view') }}

-- ECCDM Entity: CancerTreatment
-- Interventions administered to treat a cancer condition.
-- Categories: surgery, radiotherapy, systemic (chemo/immuno/hormonal)
-- Depends on: omop_procedure_occurrence, omop_drug_exposure, eccdm_cancer_patient

-- Surgery
SELECT
  po.procedure_occurrence_id                        AS treatment_id,
  'procedure_occurrence'                            AS source_table,
  po.person_id,
  po.procedure_concept_id                           AS treatment_concept_id,
  po.procedure_source_value                         AS treatment_code,
  'surgery'                                         AS treatment_category,
  po.procedure_date                                 AS treatment_start_date,
  CAST(NULL AS DATE)                                AS treatment_end_date,
  po.visit_occurrence_id,
  po.provider_id
FROM {{ ref('omop_procedure_occurrence') }} po
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = po.person_id
WHERE (
  LOWER(po.procedure_source_value) LIKE '%ectomy%'
  OR LOWER(po.procedure_source_value) LIKE '%excision%'
  OR LOWER(po.procedure_source_value) LIKE '%resection%'
  OR LOWER(po.procedure_source_value) LIKE '%biopsy%'
)

UNION ALL

-- Radiotherapy
SELECT
  po.procedure_occurrence_id                        AS treatment_id,
  'procedure_occurrence'                            AS source_table,
  po.person_id,
  po.procedure_concept_id                           AS treatment_concept_id,
  po.procedure_source_value                         AS treatment_code,
  'radiotherapy'                                    AS treatment_category,
  po.procedure_date                                 AS treatment_start_date,
  CAST(NULL AS DATE)                                AS treatment_end_date,
  po.visit_occurrence_id,
  po.provider_id
FROM {{ ref('omop_procedure_occurrence') }} po
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = po.person_id
WHERE (
  LOWER(po.procedure_source_value) LIKE '%radiation%'
  OR LOWER(po.procedure_source_value) LIKE '%radiotherapy%'
  OR LOWER(po.procedure_source_value) LIKE '%brachytherapy%'
)

UNION ALL

-- Systemic treatment (chemotherapy, immunotherapy, hormonal)
SELECT
  de.drug_exposure_id                               AS treatment_id,
  'drug_exposure'                                   AS source_table,
  de.person_id,
  de.drug_concept_id                                AS treatment_concept_id,
  de.drug_source_value                              AS treatment_code,
  'systemic'                                        AS treatment_category,
  de.drug_exposure_start_date                       AS treatment_start_date,
  de.drug_exposure_end_date                         AS treatment_end_date,
  de.visit_occurrence_id,
  de.provider_id
FROM {{ ref('omop_drug_exposure') }} de
INNER JOIN {{ ref('eccdm_cancer_patient') }} cp
  ON cp.person_id = de.person_id
WHERE (
  -- Common oncology drug classes
  LOWER(de.drug_source_value) LIKE '%cisplatin%'
  OR LOWER(de.drug_source_value) LIKE '%carboplatin%'
  OR LOWER(de.drug_source_value) LIKE '%doxorubicin%'
  OR LOWER(de.drug_source_value) LIKE '%paclitaxel%'
  OR LOWER(de.drug_source_value) LIKE '%fluorouracil%'
  OR LOWER(de.drug_source_value) LIKE '%cyclophosphamide%'
  OR LOWER(de.drug_source_value) LIKE '%tamoxifen%'
  OR LOWER(de.drug_source_value) LIKE '%pembrolizumab%'
  OR LOWER(de.drug_source_value) LIKE '%nivolumab%'
  OR LOWER(de.drug_source_value) LIKE '%trastuzumab%'
  OR LOWER(de.drug_source_value) LIKE '%bevacizumab%'
  OR LOWER(de.drug_source_value) LIKE '%methotrexate%'
  OR LOWER(de.drug_source_value) LIKE '%gemcitabine%'
  OR LOWER(de.drug_source_value) LIKE '%irinotecan%'
  OR LOWER(de.drug_source_value) LIKE '%oxaliplatin%'
)
