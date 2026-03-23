# 🏥 Avalon Analytics

**Healthcare analytics powered by OMOP CDM 5.4 — query clinical data, score patient risk, and build ML models using natural language.**

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![FHIR](https://img.shields.io/badge/FHIR-R4-orange.svg)](https://hl7.org/fhir/R4/)
[![OMOP](https://img.shields.io/badge/OMOP-CDM%205.4-green.svg)](https://ohdsi.github.io/CommonDataModel/cdm54.html)
[![BigQuery](https://img.shields.io/badge/BigQuery-Analytics%20Hub-4285F4.svg)](https://console.cloud.google.com/bigquery/analytics-hub)

---

## What is Avalon?

Avalon Analytics transforms raw clinical data into actionable insights — without requiring a data science team.

It provides:

- **9 OMOP CDM 5.4 views** — production-ready, research-grade data model on FHIR-normalized data in BigQuery
- **5 pre-trained clinical ML models** — readmission prediction, mortality risk, patient segmentation, lab forecasting, drug-condition analysis
- **HRRP savings calculator** — quantify CMS penalty exposure and ROI from reducing readmissions
- **Natural language interface** — ask clinical questions in English, get SQL results and trained models (powered by Gemini)
- **Synthetic data sandbox** — explore everything with realistic Synthea-generated data at zero risk

### Who is it for?

| Role | What Avalon provides |
|------|---------------------|
| **CMO / Quality** | Readmission risk scores, mortality benchmarks, population insights |
| **CFO / Revenue Cycle** | HRRP penalty calculator with dollar-amount savings projections |
| **Population Health** | Patient segmentation into actionable care management cohorts |
| **Clinical Research** | OMOP-compliant datasets compatible with OHDSI tools (ATLAS, ACHILLES) |
| **Pharmacy / P&T** | Drug-condition co-occurrence matrix with lift scores |

---

## Architecture

```
  Your Data                        Your BigQuery Project
  ─────────                        ────────────────────
  ┌─────────┐     ┌──────────┐     ┌──────────────────────────────┐
  │ EHR     │────►│  Forge   │────►│  OMOP Views  │  ML Models   │
  │ (FHIR)  │     │ Normalize│     │  (9 tables)  │  (5 models)  │
  └─────────┘     └──────────┘     │              │              │
                                   │     Ask a question ──► SQL  │
                                   │     Describe a model ──► ML │
                                   └──────────────────────────────┘
                                     All queries run here.
                                     PHI never leaves your project.
```

**Key architectural principle:** In production, all analytics run inside *your* BigQuery project. Your clinical data never leaves your GCP environment.

---

## OMOP CDM 5.4 Views

Avalon maps FHIR R4 resources to OMOP CDM 5.4 views following the [OHDSI Common Data Model specification](https://ohdsi.github.io/CommonDataModel/cdm54.html).

| View | FHIR Source | Key Fields | OMOP Table |
|------|------------|------------|------------|
| `omop_person` | Patient | person_id, gender, birth year, race, ethnicity | [PERSON](https://ohdsi.github.io/CommonDataModel/cdm54.html#PERSON) |
| `omop_observation_period` | Encounter (agg) | observation_period_start/end_date | [OBSERVATION_PERIOD](https://ohdsi.github.io/CommonDataModel/cdm54.html#OBSERVATION_PERIOD) |
| `omop_visit_occurrence` | Encounter | visit_type (IP/OP/ED), dates, LOS | [VISIT_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#VISIT_OCCURRENCE) |
| `omop_condition_occurrence` | Condition | SNOMED codes, onset/resolution dates | [CONDITION_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#CONDITION_OCCURRENCE) |
| `omop_procedure_occurrence` | Procedure | SNOMED codes, procedure dates | [PROCEDURE_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#PROCEDURE_OCCURRENCE) |
| `omop_drug_exposure` | MedicationRequest | RxNorm codes, start/end dates | [DRUG_EXPOSURE](https://ohdsi.github.io/CommonDataModel/cdm54.html#DRUG_EXPOSURE) |
| `omop_measurement` | Observation (numeric) | LOINC codes, values, units | [MEASUREMENT](https://ohdsi.github.io/CommonDataModel/cdm54.html#MEASUREMENT) |
| `omop_observation` | Observation (non-numeric) | Clinical findings, assessments | [OBSERVATION](https://ohdsi.github.io/CommonDataModel/cdm54.html#OBSERVATION) |
| `omop_death` | Patient (deceased) | Death date, cause of death | [DEATH](https://ohdsi.github.io/CommonDataModel/cdm54.html#DEATH) |

**ID generation:** Deterministic IDs via `ABS(FARM_FINGERPRINT(resource_id))` for referential integrity across all views.

For full field specifications, see [docs/omop_view_specs.md](docs/omop_view_specs.md).

---

## ML Models

| Model | Type | What It Does |
|-------|------|-------------|
| `readmission_predictor` | Logistic Regression | Predicts 30-day hospital readmission risk from demographics, comorbidities, and visit history |
| `mortality_risk` | Logistic Regression | Scores patient mortality risk using age, condition burden, and utilization patterns |
| `patient_segments` | K-Means (k=5) | Identifies 5 patient archetypes from utilization, condition burden, and polypharmacy |
| `lab_trend_forecast` | ARIMA+ (12-month) | Forecasts population-level lab value trends for 10 common lab types |
| `drug_condition_matrix` | Analytical View | Drug-condition co-occurrence with lift scores for pharmacovigilance |

All models are trained using [BigQuery ML](https://cloud.google.com/bigquery/docs/bqml-introduction) and run entirely within your BigQuery project.

---

## Sample Queries

See the full query library in [docs/sample_queries.md](docs/sample_queries.md). Here are a few examples:

### Patient Demographics
```sql
SELECT
  gender_source_value,
  COUNT(*) AS patient_count,
  AVG(EXTRACT(YEAR FROM CURRENT_DATE()) - year_of_birth) AS avg_age
FROM omop_person
GROUP BY gender_source_value;
```

### 30-Day Readmission Rate
```sql
WITH visits AS (
  SELECT person_id, visit_start_date, visit_end_date,
         LEAD(visit_start_date) OVER (
           PARTITION BY person_id ORDER BY visit_start_date
         ) AS next_visit_date
  FROM omop_visit_occurrence
  WHERE visit_concept_id = 9201  -- inpatient
)
SELECT
  ROUND(COUNT(CASE WHEN DATE_DIFF(next_visit_date, visit_end_date, DAY) <= 30
                   THEN 1 END) * 100.0 / COUNT(*), 1) AS readmission_rate_pct
FROM visits;
```

### Top Conditions by Frequency
```sql
SELECT
  condition_source_value AS snomed_code,
  COUNT(*) AS occurrence_count,
  COUNT(DISTINCT person_id) AS unique_patients
FROM omop_condition_occurrence
GROUP BY condition_source_value
ORDER BY occurrence_count DESC
LIMIT 20;
```

---

## Try It Free

Avalon's synthetic dataset is available on [BigQuery Analytics Hub](https://console.cloud.google.com/bigquery/analytics-hub/discovery/projects/foxtrot-communications-public/locations/us/dataExchanges/forge_synthetic_fhir/listings/fhir_r4_synthetic_data):

1. Subscribe to the dataset (free, requires GCP account)
2. Open BigQuery console
3. Run any of the sample queries above

---

## Integration

Avalon integrates with the [Forge](https://github.com/foxtrotcommunications) data platform for FHIR normalization. For integration details, see [docs/integration.md](docs/integration.md).

### Supported Data Sources

| Source | Format | Status |
|--------|--------|--------|
| Synthea (synthetic) | FHIR R4 | ✅ Production |
| Epic | FHIR R4 (US Core) | 🔜 Planned |
| Cerner / Oracle Health | FHIR R4 | 🔜 Planned |
| athenahealth | FHIR R4 + proprietary | 🔜 Planned |

---

## Repository Structure

```
avalon-public/
├── README.md                    # This file
├── LICENSE                      # Apache 2.0
├── CONTRIBUTING.md              # Contribution guidelines
├── SECURITY.md                  # Security policy
└── docs/
    ├── omop_view_specs.md       # OMOP CDM 5.4 view field specifications
    ├── sample_queries.md        # SQL query library for OMOP views
    └── integration.md           # Forge integration guide
```

> **Note:** The Avalon analytics engine, ML model definitions, and deployment infrastructure are maintained in a private repository. This public repo provides documentation, specifications, and sample queries.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. We welcome:

- 🐛 Bug reports and feature requests via Issues
- 📖 Documentation improvements
- 🔬 Sample query contributions
- 🗺️ Healthcare terminology mapping suggestions

---

## License

[Apache License 2.0](LICENSE)

---

_Avalon Analytics is a [Foxtrot Communications](https://foxtrotcommunications.net) product, powered by [Forge](https://github.com/foxtrotcommunications)._
