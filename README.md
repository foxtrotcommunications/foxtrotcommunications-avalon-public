# 🏥 Avalon Analytics — Open Source

**OMOP CDM 5.4 analytics marketplace built on [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) normalized FHIR data.**

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![FHIR](https://img.shields.io/badge/FHIR-R4-orange.svg)](https://hl7.org/fhir/R4/)
[![OMOP](https://img.shields.io/badge/OMOP-CDM%205.4-green.svg)](https://ohdsi.github.io/CommonDataModel/cdm54.html)
[![CI](https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public/actions/workflows/ci.yml/badge.svg)](https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public/actions)

---

## What's in This Repo

This is the **open source analytics layer** for the Avalon platform. It contains everything needed to build production-grade OMOP CDM 5.4 tables from forge-core's normalized FHIR output, ECCDM cancer analytics views, plus a marketplace of analytics packages that run on those tables.

| Component | What It Does | Path |
|-----------|-------------|------|
| **OMOP dbt Models** | 17 OMOP CDM 5.4 tables built on forge-core `root__` tables | [`omop-views/models/omop/`](omop-views/models/omop/) |
| **ECCDM Views** | 6 European Cancer Common Data Model views built on OMOP | [`omop-views/models/eccdm/`](omop-views/models/eccdm/) |
| **Analytics Packages** | Plug-and-play analytics (HRRP, etc.) with SQL + viz specs | [`packages/`](packages/) |
| **Forge Table Contract** | Machine-readable schema defining the forge-core → OMOP interface | [`forge-table-contract/`](forge-table-contract/) |

---

## Architecture

```
  FHIR R4 JSON
       │
       ▼
  ┌──────────────────────┐
  │  forge-core (OSS)    │  JSON → relational decomposition
  │  github.com/foxtrot  │  Produces root__root, root__root__raw_1, etc.
  │  communications/     │
  │  forge-core          │
  └──────────┬───────────┘
             │ root__ tables (per-resource datasets)
             ▼
   ┌──────────────────────┐
   │  THIS REPO (OSS)     │  dbt models: staging → OMOP → ECCDM
   │  omop-views/         │  Analytics packages query OMOP tables
   │  packages/           │  ECCDM views for cancer analytics
   └──────────┬───────────┘
             │ OMOP CDM 5.4 tables
             ▼
  ┌──────────────────────┐
  │  Avalon SaaS         │  NL-to-SQL, ML models, orchestration
  │  (proprietary)       │  Consumes OMOP tables + analytics packages
  └──────────────────────┘
```

The key structural advantage: all analytics — open source and commercial — operate on the same **forge-normalized schema**. This means any OMOP view or analytics package written here works with any forge-core deployment, on any warehouse forge-core supports (BigQuery, Snowflake, Databricks, Postgres, Redshift).

---

## Quick Start

### Prerequisites
- [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) has processed your FHIR data
- dbt 1.7+ with the appropriate adapter (e.g., `dbt-bigquery`)

### Build OMOP Tables

```bash
git clone https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public.git
cd foxtrotcommunications-avalon-public/omop-views

# Set your forge project
export FORGE_PROJECT=your-gcp-project

# Run all models
dbt run --profile forge --target your_target
```

### Explore Analytics

Browse `packages/` for available analytics. Each package has a `manifest.json` describing its inputs, parameters, and outputs. See the [Package Authoring Guide](packages/README.md).

---

## OMOP Models (`models/omop/`)

| Model | OMOP Table | Description |
|-------|------------|-------------|
| `omop_person` | PERSON | One row per patient — demographics, gender, birth year |
| `omop_location` | LOCATION | Unique city/state/zip combinations |
| `omop_visit_occurrence` | VISIT_OCCURRENCE | One row per encounter |
| `omop_observation_period` | OBSERVATION_PERIOD | Observation window per patient |
| `omop_condition_occurrence` | CONDITION_OCCURRENCE | One row per condition event |
| `omop_procedure_occurrence` | PROCEDURE_OCCURRENCE | One row per procedure event |
| `omop_drug_exposure` | DRUG_EXPOSURE | One row per medication event |
| `omop_measurement` | MEASUREMENT | Numeric observations (labs) |
| `omop_observation` | OBSERVATION | Non-numeric clinical findings |
| `omop_death` | DEATH | Deceased patients |
| `omop_cost` | COST | Claim item-level costs |
| `omop_payer_plan_period` | PAYER_PLAN_PERIOD | Coverage periods per patient+insurer |
| `omop_provider` | PROVIDER | Derived from encounter participants |
| `omop_care_site` | CARE_SITE | Derived from encounter service providers |
| `omop_cdm_source` | CDM_SOURCE | Required OMOP metadata row |
| `omop_condition_era` | CONDITION_ERA | Condition persistence windows (30-day) |
| `omop_drug_era` | DRUG_ERA | Drug persistence windows (30-day) |

All models pull data exclusively from forge-core's child sub-tables (`root__root__raw_1` and descendants). For full specifications, see [docs/omop_view_specs.md](docs/omop_view_specs.md).

---

## ECCDM Views (`models/eccdm/`)

Implementation of the [European Cancer Common Data Model](https://build.fhir.org/ig/hl7-eu/cancer-common/conceptualmodel.html) (HL7 EU Cancer Common IG). All 6 views are materialized as views with `ref()` dependencies on upstream OMOP tables.

| Model | ECCDM Entity | Depends On |
|-------|-------------|------------|
| `eccdm_cancer_patient` | CancerPatient | omop_person, omop_observation_period, omop_condition_occurrence, omop_death |
| `eccdm_cancer_condition` | CancerConditionAtDiagnosis | omop_condition_occurrence, omop_person |
| `eccdm_cancer_stage` | CancerStage (TNM) | omop_measurement |
| `eccdm_cancer_treatment` | CancerTreatment | omop_procedure_occurrence, omop_drug_exposure, eccdm_cancer_patient |
| `eccdm_treatment_response` | TreatmentResponse | omop_measurement, eccdm_cancer_patient |
| `eccdm_follow_up` | LastFollowUp | omop_visit_occurrence, eccdm_cancer_patient, eccdm_cancer_condition, eccdm_cancer_treatment |

Filters cancer patients by ICD-10 C00–C97 codes (excluding C44 non-melanoma skin cancer). Includes TNM staging (clinical + pathological), treatment categorization (surgery, radiotherapy, systemic), tumor marker tracking (PSA, CEA, CA-125, CA-19-9), and follow-up with vital status.

---

## Analytics Packages

| Package | Category | Description |
|---------|----------|-------------|
| [HRRP Readmission Penalty](packages/hrrp-readmission-penalty/) | Cost & Quality | CMS HRRP penalty exposure scorecard with 30-day readmission tracking |

### Contributing a Package

See the [Package Authoring Guide](packages/README.md) for the manifest format, directory structure, and validation requirements.

---

## Repository Structure

```
avalon-public/
├── omop-views/                       # dbt project
│   ├── dbt_project.yml               # Config with forge dataset vars
│   ├── macros/forge_join.sql          # Reusable idx segment matching
│   └── models/
│       ├── staging/                   # FHIR → flat views
│       │   ├── _sources.yml           # Source definitions
│       │   ├── _vocab_sources.yml     # Vocabulary source definitions
│       │   ├── schema.yml             # Staging model tests
│       │   ├── stg_patient.sql
│       │   ├── stg_encounter.sql
│       │   └── ...
│       ├── omop/                      # OMOP CDM 5.4 tables (17 models)
│       │   ├── schema.yml             # OMOP model tests
│       │   ├── omop_person.sql
│       │   ├── omop_visit_occurrence.sql
│       │   └── ...
│       └── eccdm/                     # ECCDM cancer views (6 models)
│           ├── schema.yml             # ECCDM model tests
│           ├── eccdm_cancer_patient.sql
│           ├── eccdm_cancer_condition.sql
│           └── ...
├── packages/                          # Analytics marketplace
│   └── hrrp-readmission-penalty/
│       ├── manifest.json
│       ├── queries/
│       └── viz/
├── forge-table-contract/              # Interface contract
│   └── contract.json
├── .github/
│   ├── workflows/ci.yml              # SQL lint + manifest validation
│   └── CODEOWNERS
├── docs/
├── hrrp/                              # Legacy HRRP calculator
├── LICENSE                            # Apache 2.0
├── CONTRIBUTING.md
└── SECURITY.md
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). We welcome:

- 🔬 New analytics packages
- 📐 OMOP view improvements and vocabulary mapping
- 🧪 dbt tests and data quality checks
- 📖 Documentation improvements
- 🗺️ Ports to additional warehouse dialects

All PRs require CI to pass (SQL linting, manifest validation, contract integrity checks) and core team review.

---

## License

[Apache License 2.0](LICENSE)

---

_Avalon Analytics is a [Foxtrot Communications](https://foxtrotcommunications.net) product, powered by [Forge](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core)._
