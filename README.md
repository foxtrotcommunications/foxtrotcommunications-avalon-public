# 🏥 Avalon Analytics — Open Source

**OMOP CDM 5.4 analytics marketplace built on [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) normalized FHIR data.**

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![FHIR](https://img.shields.io/badge/FHIR-R4-orange.svg)](https://hl7.org/fhir/R4/)
[![OMOP](https://img.shields.io/badge/OMOP-CDM%205.4-green.svg)](https://ohdsi.github.io/CommonDataModel/cdm54.html)
[![CI](https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public/actions/workflows/ci.yml/badge.svg)](https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public/actions)

---

## What's in This Repo

This is the **open source analytics layer** for the Avalon platform. It contains everything needed to build production-grade OMOP CDM 5.4 tables from forge-core's normalized FHIR output, plus a marketplace of analytics packages that run on those tables.

| Component | What It Does | Path |
|-----------|-------------|------|
| **OMOP dbt Models** | 9 OMOP CDM 5.4 tables built on forge-core `root__` tables | [`omop-views/`](omop-views/) |
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
  │  THIS REPO (OSS)     │  dbt models: staging → OMOP tables
  │  omop-views/         │  Analytics packages query OMOP tables
  │  packages/           │
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

## OMOP Models

| Model | OMOP Table | Forge Source Tables |
|-------|------------|---------------------|
| `omop_person` | PERSON | `root__root__raw_1`, extension sub-tables |
| `omop_visit_occurrence` | VISIT_OCCURRENCE | `root__root__raw_1`, class/period/participant |
| `omop_observation_period` | OBSERVATION_PERIOD | (aggregated from encounters) |
| `omop_condition_occurrence` | CONDITION_OCCURRENCE | `root__root__raw_1`, code/subject/encounter |
| `omop_procedure_occurrence` | PROCEDURE_OCCURRENCE | `root__root__raw_1`, code/perf/subject |
| `omop_drug_exposure` | DRUG_EXPOSURE | `root__root__raw_1`, medication coding |
| `omop_measurement` | MEASUREMENT | `root__root__raw_1`, code/value |
| `omop_observation` | OBSERVATION | `root__root__raw_1`, code/value |
| `omop_death` | DEATH | patient deceased + same-day conditions |

All models pull data exclusively from forge-core's child sub-tables (`root__root__raw_1` and descendants). `root__root` is used only as the ingestion anchor for deduplication.

For full specifications, see [docs/omop_view_specs.md](docs/omop_view_specs.md).

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
│       ├── staging/                   # Views joining root__ sub-tables
│       │   ├── _sources.yml           # Source definitions
│       │   ├── stg_patient.sql
│       │   ├── stg_encounter.sql
│       │   └── ...
│       ├── omop_person.sql            # Materialized OMOP tables
│       ├── omop_visit_occurrence.sql
│       └── ...
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
