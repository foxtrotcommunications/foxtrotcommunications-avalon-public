# OMOP CDM 5.4 View Specifications

Avalon maps FHIR R4 resources to the [OMOP Common Data Model v5.4](https://ohdsi.github.io/CommonDataModel/cdm54.html). This document specifies the field mappings for each view.

---

## omop_person

Maps FHIR `Patient` resources to the OMOP [PERSON](https://ohdsi.github.io/CommonDataModel/cdm54.html#PERSON) table.

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `person_id` | INT64 | `FARM_FINGERPRINT(resource_id)` | Deterministic ID |
| `gender_concept_id` | INT64 | `Patient.gender` | 8507 (male), 8532 (female) |
| `year_of_birth` | INT64 | `Patient.birthDate` | Birth year |
| `month_of_birth` | INT64 | `Patient.birthDate` | Birth month |
| `day_of_birth` | INT64 | `Patient.birthDate` | Birth day |
| `birth_datetime` | TIMESTAMP | `Patient.birthDate` | Full birth timestamp |
| `race_concept_id` | INT64 | — | OMOP concept (pending vocabulary integration) |
| `ethnicity_concept_id` | INT64 | — | OMOP concept (pending vocabulary integration) |
| `person_source_value` | STRING | `Patient.id` | Original FHIR resource ID |
| `gender_source_value` | STRING | `Patient.gender` | Original gender string |

---

## omop_observation_period

Derived from aggregated FHIR `Encounter` resources. Maps to OMOP [OBSERVATION_PERIOD](https://ohdsi.github.io/CommonDataModel/cdm54.html#OBSERVATION_PERIOD).

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `observation_period_id` | INT64 | Generated | Row number per patient |
| `person_id` | INT64 | `Encounter.subject` | Patient reference |
| `observation_period_start_date` | DATE | `MIN(Encounter.period.start)` | Earliest encounter |
| `observation_period_end_date` | DATE | `MAX(Encounter.period.end)` | Latest encounter |
| `period_type_concept_id` | INT64 | Constant | 44814724 (EHR) |

---

## omop_visit_occurrence

Maps FHIR `Encounter` resources to OMOP [VISIT_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#VISIT_OCCURRENCE).

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `visit_occurrence_id` | INT64 | `FARM_FINGERPRINT(resource_id)` | Deterministic ID |
| `person_id` | INT64 | `Encounter.subject` | Patient reference |
| `visit_concept_id` | INT64 | `Encounter.class.code` | 9201 (IP), 9202 (OP), 9203 (ED) |
| `visit_start_date` | DATE | `Encounter.period.start` | Visit start |
| `visit_start_datetime` | TIMESTAMP | `Encounter.period.start` | Visit start (timestamp) |
| `visit_end_date` | DATE | `Encounter.period.end` | Visit end |
| `visit_end_datetime` | TIMESTAMP | `Encounter.period.end` | Visit end (timestamp) |
| `visit_type_concept_id` | INT64 | Constant | 44818518 (EHR) |
| `visit_source_value` | STRING | `Encounter.class.code` | Original class code |

---

## omop_condition_occurrence

Maps FHIR `Condition` resources to OMOP [CONDITION_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#CONDITION_OCCURRENCE).

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `condition_occurrence_id` | INT64 | `FARM_FINGERPRINT(resource_id)` | Deterministic ID |
| `person_id` | INT64 | `Condition.subject` | Patient reference |
| `condition_concept_id` | INT64 | `Condition.code.coding[0].code` | OMOP concept (SNOMED → OMOP mapping) |
| `condition_start_date` | DATE | `Condition.onsetDateTime` | Condition onset |
| `condition_end_date` | DATE | `Condition.abatementDateTime` | Condition resolution |
| `condition_type_concept_id` | INT64 | Constant | 32020 (EHR encounter diagnosis) |
| `condition_source_value` | STRING | `Condition.code.coding[0].code` | Original SNOMED code |
| `condition_source_concept_id` | INT64 | — | Source vocabulary concept |

---

## omop_procedure_occurrence

Maps FHIR `Procedure` resources to OMOP [PROCEDURE_OCCURRENCE](https://ohdsi.github.io/CommonDataModel/cdm54.html#PROCEDURE_OCCURRENCE).

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `procedure_occurrence_id` | INT64 | `FARM_FINGERPRINT(resource_id)` | Deterministic ID |
| `person_id` | INT64 | `Procedure.subject` | Patient reference |
| `procedure_concept_id` | INT64 | `Procedure.code.coding[0].code` | OMOP concept (SNOMED → OMOP mapping) |
| `procedure_date` | DATE | `Procedure.performedDateTime` | Procedure date |
| `procedure_type_concept_id` | INT64 | Constant | 38000275 (EHR) |
| `procedure_source_value` | STRING | `Procedure.code.coding[0].code` | Original SNOMED code |

---

## omop_drug_exposure

Maps FHIR `MedicationRequest` resources to OMOP [DRUG_EXPOSURE](https://ohdsi.github.io/CommonDataModel/cdm54.html#DRUG_EXPOSURE).

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `drug_exposure_id` | INT64 | `FARM_FINGERPRINT(resource_id)` | Deterministic ID |
| `person_id` | INT64 | `MedicationRequest.subject` | Patient reference |
| `drug_concept_id` | INT64 | `MedicationRequest.medicationCodeableConcept` | OMOP concept (RxNorm → OMOP mapping) |
| `drug_exposure_start_date` | DATE | `MedicationRequest.authoredOn` | Prescription date |
| `drug_exposure_end_date` | DATE | Derived | End of prescription period |
| `drug_type_concept_id` | INT64 | Constant | 38000177 (prescription written) |
| `drug_source_value` | STRING | `MedicationRequest.medicationCodeableConcept.coding[0].code` | Original RxNorm code |

---

## omop_measurement

Maps numeric FHIR `Observation` resources to OMOP [MEASUREMENT](https://ohdsi.github.io/CommonDataModel/cdm54.html#MEASUREMENT).

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `measurement_id` | INT64 | `FARM_FINGERPRINT(resource_id)` | Deterministic ID |
| `person_id` | INT64 | `Observation.subject` | Patient reference |
| `measurement_concept_id` | INT64 | `Observation.code.coding[0].code` | OMOP concept (LOINC → OMOP mapping) |
| `measurement_date` | DATE | `Observation.effectiveDateTime` | Measurement date |
| `value_as_number` | FLOAT64 | `Observation.valueQuantity.value` | Numeric result |
| `unit_source_value` | STRING | `Observation.valueQuantity.unit` | Unit of measurement |
| `measurement_source_value` | STRING | `Observation.code.coding[0].code` | Original LOINC code |

---

## omop_observation

Maps non-numeric FHIR `Observation` resources to OMOP [OBSERVATION](https://ohdsi.github.io/CommonDataModel/cdm54.html#OBSERVATION).

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `observation_id` | INT64 | `FARM_FINGERPRINT(resource_id)` | Deterministic ID |
| `person_id` | INT64 | `Observation.subject` | Patient reference |
| `observation_concept_id` | INT64 | `Observation.code.coding[0].code` | OMOP concept |
| `observation_date` | DATE | `Observation.effectiveDateTime` | Observation date |
| `observation_type_concept_id` | INT64 | Constant | 38000280 (observation recorded from EHR) |
| `observation_source_value` | STRING | `Observation.code.coding[0].code` | Original code |

---

## omop_death

Maps deceased FHIR `Patient` resources to OMOP [DEATH](https://ohdsi.github.io/CommonDataModel/cdm54.html#DEATH).

| OMOP Field | Type | FHIR Source | Description |
|-----------|------|-------------|-------------|
| `person_id` | INT64 | `FARM_FINGERPRINT(resource_id)` | Patient ID |
| `death_date` | DATE | `Patient.deceasedDateTime` | Date of death |
| `death_datetime` | TIMESTAMP | `Patient.deceasedDateTime` | Timestamp of death |
| `death_type_concept_id` | INT64 | Constant | 32510 (EHR) |
| `cause_source_value` | STRING | — | Cause of death (if available) |

---

## Terminology Mappings

| FHIR Vocabulary | OMOP Vocabulary | Status |
|----------------|-----------------|--------|
| Gender (male/female) | OMOP Gender (8507/8532) | ✅ Mapped |
| Visit class (AMB/IMP/EMER) | OMOP Visit (9201/9202/9203) | ✅ Mapped |
| SNOMED CT (conditions, procedures) | OMOP Standard Concepts | 🔜 In progress |
| LOINC (measurements) | OMOP Standard Concepts | 🔜 In progress |
| RxNorm (drugs) | OMOP Standard Concepts | 🔜 In progress |
| CVX (immunizations) | OMOP Standard Concepts | 🔜 Planned |

---

## References

- [OMOP CDM 5.4 Specification](https://ohdsi.github.io/CommonDataModel/cdm54.html)
- [OHDSI Book of OHDSI](https://ohdsi.github.io/TheBookOfOhdsi/)
- [ATHENA Vocabulary Browser](https://athena.ohdsi.org/)
- [FHIR R4 Specification](https://hl7.org/fhir/R4/)
