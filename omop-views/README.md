# Avalon OMOP — dbt Package

OMOP CDM 5.4 models built directly on [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) normalized tables.

## Architecture

```
forge-core (dbt)              this package (dbt)
─────────────────             ──────────────────
FHIR JSON                     staging/
  → frg__root                   stg_patient.sql ──→ omop_person
  → frg__root__raw_1            stg_encounter.sql ─→ omop_visit_occurrence
  → frg__root__raw_1__clas1     stg_condition.sql ─→ omop_condition_occurrence
  → frg__root__raw_1__peri1     stg_procedure.sql ─→ omop_procedure_occurrence
  → ...                         stg_observation.sql → omop_measurement
                                                      omop_observation
                                stg_medication_request.sql → omop_drug_exposure
```

Staging models are **views** that join forge-core's sub-tables (the `frg__` tables) into flat, queryable shapes. OMOP models are **materialized tables** that map those shapes to the OMOP CDM 5.4 schema.

## Prerequisites

- [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) must have processed your FHIR data
- dbt 1.7+ with BigQuery adapter (`dbt-bigquery`)
- The forge normalized datasets must exist (e.g., `fhir_normalized_patient`, `fhir_normalized_encounter`, etc.)

## Quick Start

```bash
# Clone
git clone https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public.git
cd foxtrotcommunications-avalon-public/omop-views

# Configure your forge project
export FORGE_PROJECT=your-gcp-project

# Run
dbt run --profile forge --target your_target
```

## Configuration

Override these variables in your `dbt_project.yml`:

```yaml
vars:
  forge_project: "your-gcp-project"
  forge_patient_dataset: "fhir_normalized_patient"
  forge_encounter_dataset: "fhir_normalized_encounter"
  # ... etc
```

## Models

| Model | OMOP Table | Source Staging | forge-core Tables |
|-------|------------|---------------|-------------------|
| `omop_person` | PERSON | `stg_patient` | `frg__root`, `frg__root__raw_1`, extension sub-tables |
| `omop_visit_occurrence` | VISIT_OCCURRENCE | `stg_encounter` | `frg__root`, class/period/participant sub-tables |
| `omop_observation_period` | OBSERVATION_PERIOD | `stg_encounter` | (aggregated from encounters) |
| `omop_condition_occurrence` | CONDITION_OCCURRENCE | `stg_condition` | `frg__root`, `frg__root__raw_1` |
| `omop_procedure_occurrence` | PROCEDURE_OCCURRENCE | `stg_procedure` | `frg__root`, `frg__root__raw_1`, perf sub-table |
| `omop_drug_exposure` | DRUG_EXPOSURE | `stg_medication_request` | `frg__root`, medication coding sub-tables |
| `omop_measurement` | MEASUREMENT | `stg_observation` | `frg__root` (numeric only) |
| `omop_observation` | OBSERVATION | `stg_observation` | `frg__root` (non-numeric only) |
| `omop_death` | DEATH | `stg_patient` + `stg_condition` | patient deceased + same-day conditions |

## The `forge_join` Macro

All staging models use the `forge_join` macro to join forge-core sub-tables:

```sql
{{ forge_join('raw', 'forge_patient', 'frg__root__raw_1', 'r', 'frg__root') }}
```

This generates the positional `idx` segment matching that forge-core uses to link parent → child tables. See `macros/forge_join.sql` for details.
