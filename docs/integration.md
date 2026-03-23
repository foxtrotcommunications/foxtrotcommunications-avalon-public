# Forge Integration Guide

Avalon Analytics runs on top of data normalized by the [Forge](https://github.com/foxtrotcommunications) data platform. This document describes how Avalon connects to the Forge ecosystem.

---

## How It Works

```
  Data Source                Forge                    Avalon
  ───────────               ─────                    ──────
  ┌──────────┐   FHIR R4   ┌────────────┐   flat    ┌──────────────┐
  │ EHR      │────────────►│ Normalize  │──tables──►│ OMOP Views   │
  │ (Epic,   │             │ (459+ flds)│           │ ML Models    │
  │  Cerner, │             └────────────┘           │ Calculators  │
  │  athena) │                                      └──────────────┘
  └──────────┘                                       Runs in YOUR
                                                     BigQuery project
```

1. **Data sources** send FHIR R4 resources (Patient, Encounter, Condition, etc.)
2. **Forge** normalizes raw FHIR JSON into clean, flat BigQuery tables with documented schemas
3. **Avalon** deploys OMOP CDM 5.4 views and ML models on top of those normalized tables

---

## Forge-Normalized Tables

Avalon's OMOP views expect Forge-normalized tables in the target BigQuery dataset. Each FHIR resource type gets its own table:

| Forge Table | FHIR Resource | Key Normalized Fields |
|------------|---------------|----------------------|
| `patient` | Patient | resource_id, birth_date, gender, race, address |
| `encounter` | Encounter | resource_id, patient_id, class, period, status |
| `condition` | Condition | resource_id, patient_id, code, onset, abatement |
| `procedure` | Procedure | resource_id, patient_id, code, performed_date |
| `medicationrequest` | MedicationRequest | resource_id, patient_id, medication_code, authored_on |
| `observation` | Observation | resource_id, patient_id, code, value, effective_date |
| `diagnosticreport` | DiagnosticReport | resource_id, patient_id, code, issued, result |
| `immunization` | Immunization | resource_id, patient_id, vaccine_code, occurrence_date |

### Table Structure

All Forge tables follow a consistent structure:

```
table_name/
├── frg.root.resource_id       (STRING)  — FHIR resource identifier
├── frg.root.patient_id        (STRING)  — Patient reference
├── frg.root.raw_json          (JSON)    — Full FHIR resource
├── frg.root.[field]           (varies)  — Extracted scalar fields
└── frg.metadata.*             (varies)  — Forge processing metadata
```

---

## Avalon → Forge API Interaction

Avalon communicates with Forge services via HTTP APIs:

| Interaction | API | Purpose |
|------------|-----|---------|
| Trigger normalization | `POST /run_job` | Start a Forge normalization job |
| Pub/Sub trigger | `POST /pubsub/push` | Async job trigger via Cloud Pub/Sub |
| Run Synthea pipeline | `POST /fhir/run-synthea` | Generate synthetic data (sandbox) |
| NL translation | `POST /generate` | Gemini-powered natural language processing |

---

## Deployment Options

### Sandbox (Synthetic Data)

Uses Synthea to generate realistic FHIR R4 data, which is processed through Forge and made available on BigQuery Analytics Hub.

- **Data:** Synthetic (no PHI)
- **Location:** Foxtrot's GCP project
- **Access:** Free via Analytics Hub subscription

### Production (Customer Data)

Customer's real EHR data flows through Forge into their own BigQuery project. Avalon views and models are deployed into the customer's dataset.

- **Data:** Real clinical data (PHI)
- **Location:** Customer's GCP project
- **Access:** Customer-controlled via BigQuery IAM

---

## Requirements

| Requirement | Details |
|------------|---------|
| **GCP Project** | A Google Cloud project with BigQuery enabled |
| **BigQuery Dataset** | Forge-normalized tables in a BigQuery dataset |
| **IAM Permissions** | `roles/bigquery.dataViewer` (queries), `roles/bigquery.admin` (deploy views/models) |
| **Forge Platform** | Active Forge deployment for data normalization |

---

## Getting Started

1. **Subscribe to the sandbox** on [Analytics Hub](https://console.cloud.google.com/bigquery/analytics-hub) to explore with synthetic data
2. **Contact us** at customer_support@foxtrotcommunications.net for production deployment
3. **Run sample queries** from [docs/sample_queries.md](sample_queries.md)

---

_For more information about the Forge platform, visit [foxtrotcommunications.net](https://foxtrotcommunications.net)._
