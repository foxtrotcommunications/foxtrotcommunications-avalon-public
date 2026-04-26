# CMS HRRP Readmission Penalty — Methodology

## Overview

The **Hospital Readmissions Reduction Program (HRRP)** penalizes hospitals with excess readmission rates for six target conditions. This package implements the core penalty calculation using OMOP 5.4 `condition_occurrence` and `visit_occurrence` — **no DRG codes required**.

## Condition Categories

| ID | Condition | CMS Expected Rate (FY2024) | SNOMED Codes Used |
|---|---|---|---|
| AMI | Acute Myocardial Infarction | 16.5% | 57054005, 22298006, 401303003, 401314000 |
| HF | Heart Failure | 21.5% | 84114007, 42343007, 48447003, 417996009 |
| PN | Pneumonia | 15.0% | 233604007, 53084003, 233616003, 195900001 |
| COPD | Chronic Obstructive Pulmonary Disease | 19.8% | 13645005, 185086009, 87433001, 195967001 |

> **Note on DRGs**: Real HRRP uses MS-DRG codes to identify qualifying admissions. This package substitutes SNOMED condition codes from `omop_condition_occurrence`, which are present in both synthetic (Synthea) and real customer FHIR data. When EOB/Claim data containing DRGs is available via the BB2 ingestion pipeline, the `drg_source_value` column in `omop_cost` can augment or replace this grouper.

## Calculation Logic

### Index Admission
An inpatient or ER encounter (`visit_concept_id IN (9201, 262, 9203)`) with an HRRP-qualifying diagnosis recorded during the same visit (`visit_occurrence_id` match in `omop_condition_occurrence`).

### 30-Day Readmission
Any return inpatient or ER visit for the same patient within 30 calendar days of the index discharge date (`visit_end_date`). Does **not** require same condition — any-cause readmission, matching CMS methodology.

### Excess Readmission Ratio (ERR)
```
ERR = observed_readmission_rate / national_expected_rate
```

Where `national_expected_rate` is the CMS FY2024 published benchmark.

> **Limitation**: CMS applies risk-adjustment to the expected rate based on patient comorbidity. This package uses the unadjusted national rate. For production use, apply the [CMS risk-standardization methodology](https://www.cms.gov/Medicare/Quality-Initiatives-Patient-Assessment-Instruments/HospitalQualityInits/Downloads/Mathematical-Methods.pdf).

### Simulated HRRP Penalty
```
penalty = MAX(0, ERR - 1.0) × base_medicare_payments × 0.03
```

The 3% represents the CMS maximum penalty cap. In practice, most hospitals face 0.5–1.5% penalties. This simulation uses the cap for worst-case illustration.

## Scenario Modes

| Mode | Behavior |
|---|---|
| `baseline` | Uses real OMOP data only. Shows actual population readmission rates. |
| `high_risk` | Overlays synthetic readmission events deterministically to push all four categories above national benchmarks. Useful for demonstrating penalty exposure in a demo context. Synthetic events are flagged in the `synthetic_readmits` column. |

## Data Requirements

| Requirement | Why |
|---|---|
| `omop_cost.paid_patient_copay` populated | For patient OOP calculation. If $0, run BB2 cost calibration first. |
| ≥ 100 patients with inpatient visits | Minimum for statistically meaningful rates |
| `visit_end_date` present | Required to define the 30-day readmission window |

## References

- [CMS HRRP Program Page](https://www.cms.gov/Medicare/Medicare-Fee-for-Service-Payment/AcuteInpatientPPS/Readmissions-Reduction-Program)
- [FY2024 IPPS Final Rule — Readmissions](https://www.cms.gov/newsroom/fact-sheets/fiscal-year-fy-2024-medicare-hospital-inpatient-prospective-payment-system-ipps-and-long-term-care)
- [CMS Mathematical Methods for Risk-Standardization](https://www.cms.gov/Medicare/Quality-Initiatives-Patient-Assessment-Instruments/HospitalQualityInits/Downloads/Mathematical-Methods.pdf)
- [MedPAC March 2024 Report — Readmissions](https://www.medpac.gov)
