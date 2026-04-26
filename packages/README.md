# Analytics Package Registry

## Directory Structure

Each package lives in its own directory under `packages/`:

```
packages/
└── your-package-name/
    ├── manifest.json          # Required: package metadata and config
    ├── queries/
    │   ├── main.sql           # Required: primary output query
    │   ├── validation.sql     # Required: preflight data quality check
    │   ├── trend.sql          # Optional: trend/time-series query
    │   └── detail.sql         # Optional: drill-down detail query
    ├── viz/
    │   └── scorecard.vg.json  # Optional: Vega-Lite visualization spec
    └── docs/
        └── methodology.md     # Optional: clinical methodology documentation
```

## manifest.json

Every package must include a `manifest.json` with these required fields:

```json
{
  "id": "your-package-name",
  "version": "1.0.0",
  "name": "Human Readable Name",
  "description": "What this package does.",
  "category": "cost-quality",
  "tags": ["relevant", "tags"],
  "author": "Your Name or Org",
  "license": "Apache-2.0",
  "omop_version": "5.4",
  "required_tables": ["omop_visit_occurrence", "omop_condition_occurrence"],
  "required_columns": {
    "omop_visit_occurrence": ["visit_concept_id", "visit_start_date"]
  },
  "outputs": {
    "scorecard": {
      "primary": true,
      "query": "main.sql",
      "description": "What the primary output shows."
    }
  }
}
```

## SQL Conventions

- Use `{project}` and `{dataset}` placeholders for table references
- All queries must be valid BigQuery Standard SQL
- Include `-- Output schema:` comments documenting the result columns
- Use `validation.sql` to check data prerequisites before running expensive queries

## Validation Queries

Every package must include a `queries/validation.sql` that fails fast if required data is missing. Use BigQuery `ERROR()` for clear failure messages:

```sql
SELECT
  IF(COUNT(*) = 0,
     ERROR('No inpatient visits found — HRRP analysis requires omop_visit_occurrence with visit_concept_id = 9201'),
     'OK')
FROM `{project}.{dataset}.omop_visit_occurrence`
WHERE visit_concept_id = 9201;
```

## Categories

| Category | Description |
|----------|-------------|
| `cost-quality` | Financial and quality measures (HRRP, value-based care) |
| `population-health` | Cohort analysis, risk stratification, care gaps |
| `clinical-ops` | Operational metrics (throughput, utilization, capacity) |
| `research` | Observational research, phenotyping, study design |
| `pharmacovigilance` | Drug safety, adverse events, interaction analysis |
