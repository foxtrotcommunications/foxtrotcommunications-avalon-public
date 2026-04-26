-- ─────────────────────────────────────────────────────────────────────────────
-- hrrp-readmission-penalty · validation.sql
--
-- Pre-flight checks. Anvil runs this BEFORE main.sql.
-- Any ERROR() call aborts execution and returns a structured error to the caller:
--   { "error": "PREREQ_FAIL", "message": "..." }
--
-- Injected by Anvil:
--   {project}  — GCP project ID
--   {dataset}  — OMOP dataset name (e.g. forge_synthetic_fhir)
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Check 1: inpatient visits exist ─────────────────────────────────────────
SELECT IF(
  COUNT(*) = 0,
  ERROR('PREREQ_FAIL: omop_visit_occurrence has no inpatient or ER visits (concept 9201, 262, 9203). Ensure the Bellows FHIR ingestion has completed.'),
  NULL
)
FROM `{project}.{dataset}.omop_visit_occurrence`
WHERE visit_concept_id IN (9201, 262, 9203)
  AND visit_end_date IS NOT NULL;

-- ── Check 2: condition occurrences linked to visits ──────────────────────────
SELECT IF(
  COUNTIF(visit_occurrence_id IS NOT NULL) = 0,
  ERROR('PREREQ_FAIL: omop_condition_occurrence has no records linked to visit_occurrence_id. Verify the Avalon OMOP pipeline has run.'),
  NULL
)
FROM `{project}.{dataset}.omop_condition_occurrence`
LIMIT 10000;

-- ── Check 3: HRRP-relevant conditions present ────────────────────────────────
SELECT IF(
  COUNT(*) = 0,
  ERROR('PREREQ_FAIL: No HRRP-relevant SNOMED condition codes found (AMI, HF, PN, COPD). This population may not contain acute inpatient diagnoses. The HRRP package requires at least one of: 57054005, 22298006, 401303003, 401314000, 84114007, 42343007, 233604007, 53084003, 13645005, 185086009.'),
  NULL
)
FROM `{project}.{dataset}.omop_condition_occurrence`
WHERE condition_source_value IN (
  -- AMI
  '57054005','22298006','70422006','307140009','401303003','401314000',
  -- HF
  '84114007','42343007','48447003','417996009','441530006','56675007',
  -- PN
  '233604007','53084003','233616003','278516003','195900001',
  -- COPD
  '13645005','185086009','87433001','195967001','10567002'
);

-- ── Check 4: omop_cost populated with patient cost-sharing fields ─────────────
-- If BB2 calibration hasn't run, copay/deductible/coinsurance will all be NULL.
-- The package still works but patient OOP figures will be $0.
-- This is a WARNING, not a hard failure.
SELECT IF(
  COUNTIF(paid_patient_copay IS NOT NULL AND paid_patient_copay > 0) = 0,
  ERROR('PREREQ_WARN: omop_cost.paid_patient_copay is NULL or zero for all rows. Run the BB2 cost calibration (bluebutton_ingester.py) to populate patient cost-sharing fields. Patient OOP figures in this report will be $0.'),
  NULL
)
FROM `{project}.{dataset}.omop_cost`
WHERE claim_type = 'institutional'
LIMIT 5000;

-- ── Check 5: sufficient data volume for meaningful output ────────────────────
SELECT IF(
  COUNT(DISTINCT person_id) < 100,
  ERROR('PREREQ_FAIL: omop_visit_occurrence has fewer than 100 distinct patients with inpatient visits. HRRP analysis requires a sufficient population for statistically meaningful readmission rates.'),
  NULL
)
FROM `{project}.{dataset}.omop_visit_occurrence`
WHERE visit_concept_id IN (9201, 262, 9203)
  AND visit_end_date IS NOT NULL;
