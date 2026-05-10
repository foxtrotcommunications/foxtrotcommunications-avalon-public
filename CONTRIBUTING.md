# Contributing to Avalon Analytics

Thank you for your interest in contributing. This project defines the open source OMOP CDM 5.4 analytics layer for the [Forge](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) data platform.

## What We Accept

| Contribution Type | Examples | Review Process |
|-------------------|----------|----------------|
| **Analytics Packages** | New clinical scorecards, quality measures, cost models | Clinical review + core team |
| **OMOP View Improvements** | Vocabulary mapping, new OMOP tables, bug fixes | Core team review |
| **dbt Tests** | Schema tests, data quality assertions, contract tests | Core team review |
| **Documentation** | Guides, query examples, FHIR mapping docs | Core team review |
| **Warehouse Ports** | Snowflake/Postgres/Databricks staging models | Core team review |

## PR Requirements

All PRs must:

1. **Pass CI** — SQL linting (sqlfluff), manifest validation, contract integrity checks
2. **Be reviewed by a core maintainer** (enforced via CODEOWNERS)
3. **Include tests** for any new OMOP views or analytics packages
4. **Not modify the forge table contract** without explicit approval from `@foxtrotcommunications/core`

## Development Setup

```bash
# Clone the repo
git clone https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public.git
cd foxtrotcommunications-avalon-public

# Install dbt (BigQuery example)
pip install dbt-bigquery

# Set your forge project
export FORGE_PROJECT=your-gcp-project

# Run the OMOP models
cd omop-views
dbt run --profile forge --target your_target

# Lint SQL
pip install sqlfluff
sqlfluff lint omop-views/models/ --dialect bigquery
```

## Adding an Analytics Package

1. Create a directory under `packages/your-package-name/`
2. Add a `manifest.json` following the schema in `packages/schema.json`
3. Put SQL queries in `queries/`
4. Add a `queries/validation.sql` preflight check
5. (Optional) Add Vega-Lite viz specs in `viz/`
6. Open a PR

See `packages/hrrp-readmission-penalty/` as a reference implementation.

## Writing OMOP Models

1. **Staging models** go in `omop-views/models/staging/` and are materialized as views
2. **OMOP models** go in `omop-views/models/` and are materialized as tables
3. All data must come from forge-core child tables (`root__root__raw_1` and descendants) — never from `root__root` scalar fields
4. Use the `forge_join` macro for all sub-table joins
5. Update `_sources.yml` with any new source tables

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add omop_device_exposure model
fix: correct condition dedup logic
docs: add vocabulary mapping guide
```

## Code of Conduct

Be respectful and constructive. We're building open infrastructure for healthcare analytics — accuracy and reliability matter more than speed.

## Questions?

Open a [Discussion](https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public/discussions) or reach out to the core team.
