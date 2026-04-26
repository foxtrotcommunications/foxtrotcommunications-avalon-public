# OMOP CDM 5.4 Views

Production-ready OMOP CDM 5.4 views built on [forge-core](https://github.com/foxtrotcommunications/foxtrotcommunications-forge-core) normalized tables.

## Prerequisites

- A BigQuery or PostgreSQL dataset containing forge-core normalized tables (`patient`, `encounter`, `condition`, `procedure`, `observation`, `medication_request`, `claim`, `explanation_of_benefit`)
- See [`forge-table-contract/`](../forge-table-contract/) for the exact schema requirements

## Views

| View | FHIR Source | OMOP Table |
|------|------------|------------|
| `omop_person` | Patient | [PERSON](https://ohdsi.github.io/CommonDataModel/cdm54.html#PERSON) |
| `omop_observation_period` | Encounter (agg) | [OBSERVATION_PERIOD](https://ohdsi.github.io/CommonDataModel/cdm54.html#OBSERVATION_PERIOD) |
| `omop_provider` | Encounter.participant | [PROVIDER](https://ohdsi.github.io/CommonDataModel/cdm54.html#PROVIDER) |
| `omop_visit_occurrence` | Encounter | [VISIT_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#VISIT_OCCURRENCE) |
| `omop_condition_occurrence` | Condition | [CONDITION_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#CONDITION_OCCURRENCE) |
| `omop_procedure_occurrence` | Procedure | [PROCEDURE_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#PROCEDURE_OCCURRENCE) |
| `omop_drug_exposure` | MedicationRequest | [DRUG_EXPOSURE](https://ohdsi.github.io/CommonDataModel/cdm54.html#DRUG_EXPOSURE) |
| `omop_measurement` | Observation (numeric) | [MEASUREMENT](https://ohdsi.github.io/CommonDataModel/cdm54.html#MEASUREMENT) |
| `omop_observation` | Observation (non-numeric) | [OBSERVATION](https://ohdsi.github.io/CommonDataModel/cdm54.html#OBSERVATION) |
| `omop_death` | Patient (deceased) | [DEATH](https://ohdsi.github.io/CommonDataModel/cdm54.html#DEATH) |
| `omop_cost` | Claim + EOB | [COST](https://ohdsi.github.io/CommonDataModel/cdm54.html#COST) |
| `omop_payer_plan_period` | ExplanationOfBenefit | [PAYER_PLAN_PERIOD](https://ohdsi.github.io/CommonDataModel/cdm54.html#PAYER_PLAN_PERIOD) |

## Usage

### BigQuery

Replace `{project}` and `{dataset}` with your values, then execute each `.sql` file:

```bash
export PROJECT=my-gcp-project
export DATASET=forge_fhir

for f in bigquery/*.sql; do
  sed "s/{project}/$PROJECT/g; s/{dataset}/$DATASET/g" "$f" | bq query --use_legacy_sql=false
done
```

### PostgreSQL

```bash
export DATASET=forge_fhir

for f in postgres/*.sql; do
  sed "s/{dataset}/$DATASET/g" "$f" | psql -d your_database
done
```

## ID Generation

All views use deterministic ID generation from FHIR resource IDs:
- **BigQuery**: `ABS(FARM_FINGERPRINT(resource_id))`
- **PostgreSQL**: `ABS(('x' || md5(resource_id))::bit(64)::bigint)`

This ensures referential integrity across all OMOP tables without requiring a central ID registry.

## Vocabulary Support

Views support optional OMOP vocabulary mapping via LEFT JOINs against the Athena concept table. When a vocabulary dataset is not available, all `*_concept_id` fields default to `0` and source codes are preserved in `*_source_value` fields.
