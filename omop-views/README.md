# Avalon OMOP — dbt Package

OMOP CDM 5.4 models built directly on [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) normalized tables.

## Architecture

```
forge-core (dbt)              this package (dbt)
─────────────────             ──────────────────
FHIR JSON                     staging/
  → root__root                   stg_patient.sql ──→ omop_person
  → root__root__raw_1            stg_encounter.sql ─→ omop_visit_occurrence
  → root__root__raw_1__clas1     stg_condition.sql ─→ omop_condition_occurrence
  → root__root__raw_1__peri1     stg_procedure.sql ─→ omop_procedure_occurrence
  → ...                         stg_observation.sql → omop_measurement
                                                      omop_observation
                                stg_medication_request.sql → omop_drug_exposure
```

Staging models are **views** that join forge-core's sub-tables (the `root__` tables) into flat, queryable shapes. OMOP models are **materialized tables** that map those shapes to the OMOP CDM 5.4 schema.

## Prerequisites

- [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) must have processed your FHIR data
- dbt 1.7+ with BigQuery adapter (`dbt-bigquery`)
- The forge normalized datasets must exist (e.g., `fhir_normalized_patient`, `fhir_normalized_encounter`, etc.)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/foxtrotcommunications/foxtrotcommunications-avalon-public.git
cd foxtrotcommunications-avalon-public/omop-views

# 2. Load OMOP vocabulary (one-time setup — required for concept_id resolution)
pip install google-cloud-bigquery pandas
python scripts/load_vocab.py --project your-gcp-project --from-gcs

# 3. Configure your forge project
export FORGE_PROJECT=your-gcp-project

# 4. Run all OMOP models
dbt run --profile forge --target your_target
```

## Vocabulary Setup

All `*_concept_id` fields (e.g., `condition_concept_id`, `drug_concept_id`) are resolved
using the OHDSI Standardized Vocabularies (SNOMED CT, LOINC, RxNorm). The `load_vocab.py`
script handles loading these into BigQuery before your first `dbt run`.

### Option A — Public GCS Snapshot (recommended)

Uses a pre-filtered ~40 MB snapshot hosted by Foxtrot Communications. No Athena account needed.

```bash
python scripts/load_vocab.py \
  --project your-gcp-project \
  --from-gcs
```

### Option B — Local Athena Download

For production deployments where you want to control the vocabulary source and update cadence.

1. Create a free account at [athena.ohdsi.org](https://athena.ohdsi.org/)
2. Download a vocabulary bundle — select: **SNOMED, LOINC, RxNorm, Gender, Race, Ethnicity**
3. Extract the ZIP and point the script at the folder:

```bash
python scripts/load_vocab.py \
  --project your-gcp-project \
  --athena-dir /path/to/extracted/athena
```

### What gets loaded

| BigQuery Table | Contents |
|---|---|
| `omop_vocab.concept` | ~1.2M concepts (SNOMED + LOINC + RxNorm filtered) |
| `omop_vocab.concept_relationship` | `Maps to` and `Maps to value` relationships only |
| `omop_vocab.concept_map` | Pre-joined view: `source_code + vocabulary → standard_concept_id` |

The `concept_map` view is what all OMOP dbt models join against via the
`resolve_concept()` macro. If the vocab tables are not present, every model
gracefully falls back to `concept_id = 0` — the same behavior as the pre-vocabulary baseline.

## Configuration

Override these variables in your `dbt_project.yml`:

```yaml
vars:
  forge_project: "your-gcp-project"
  forge_patient_dataset: "fhir_normalized_patient"
  forge_encounter_dataset: "fhir_normalized_encounter"
  # ... etc

  # Vocabulary dataset (created by load_vocab.py)
  omop_vocab_project: "your-gcp-project"   # defaults to forge_project
  omop_vocab_dataset: "omop_vocab"          # default
```

## Models

| Model | OMOP Table | Source Staging | forge-core Tables |
|-------|------------|---------------|-------------------|
| `omop_person` | PERSON | `stg_patient` | `root__root`, `root__root__raw_1`, extension sub-tables |
| `omop_visit_occurrence` | VISIT_OCCURRENCE | `stg_encounter` | `root__root`, class/period/participant sub-tables |
| `omop_observation_period` | OBSERVATION_PERIOD | `stg_encounter` | (aggregated from encounters) |
| `omop_condition_occurrence` | CONDITION_OCCURRENCE | `stg_condition` | `root__root`, `root__root__raw_1` |
| `omop_procedure_occurrence` | PROCEDURE_OCCURRENCE | `stg_procedure` | `root__root`, `root__root__raw_1`, perf sub-table |
| `omop_drug_exposure` | DRUG_EXPOSURE | `stg_medication_request` | `root__root`, medication coding sub-tables |
| `omop_measurement` | MEASUREMENT | `stg_observation` | `root__root` (numeric only) |
| `omop_observation` | OBSERVATION | `stg_observation` | `root__root` (non-numeric only) |
| `omop_death` | DEATH | `stg_patient` + `stg_condition` | patient deceased + same-day conditions |

## The `forge_join` Macro

All staging models use the `forge_join` macro to join forge-core sub-tables:

```sql
{{ forge_join('raw', 'forge_patient', 'root__root__raw_1', 'r', 'root__root') }}
```

This generates the positional `idx` segment matching that forge-core uses to link parent → child tables. See `macros/forge_join.sql` for details.
