# Sample Queries for Avalon OMOP Views

A library of SQL queries for exploring clinical data through Avalon's OMOP CDM 5.4 views in BigQuery.

> **Tip:** All queries work against both the free synthetic dataset on Analytics Hub and your own production Avalon deployment.

---

## Population Overview

### Patient Demographics

```sql
SELECT
  gender_source_value AS gender,
  COUNT(*) AS patient_count,
  ROUND(AVG(EXTRACT(YEAR FROM CURRENT_DATE()) - year_of_birth), 1) AS avg_age,
  MIN(EXTRACT(YEAR FROM CURRENT_DATE()) - year_of_birth) AS min_age,
  MAX(EXTRACT(YEAR FROM CURRENT_DATE()) - year_of_birth) AS max_age
FROM omop_person
GROUP BY gender_source_value
ORDER BY patient_count DESC;
```

### Age Distribution

```sql
SELECT
  CASE
    WHEN EXTRACT(YEAR FROM CURRENT_DATE()) - year_of_birth < 18 THEN 'Pediatric (<18)'
    WHEN EXTRACT(YEAR FROM CURRENT_DATE()) - year_of_birth < 40 THEN 'Young Adult (18-39)'
    WHEN EXTRACT(YEAR FROM CURRENT_DATE()) - year_of_birth < 65 THEN 'Middle Age (40-64)'
    ELSE 'Senior (65+)'
  END AS age_group,
  COUNT(*) AS patient_count
FROM omop_person
GROUP BY age_group
ORDER BY age_group;
```

---

## Visit Patterns

### Visit Type Distribution

```sql
SELECT
  CASE visit_concept_id
    WHEN 9201 THEN 'Inpatient'
    WHEN 9202 THEN 'Outpatient'
    WHEN 9203 THEN 'Emergency'
    ELSE 'Other'
  END AS visit_type,
  COUNT(*) AS visit_count,
  COUNT(DISTINCT person_id) AS unique_patients,
  ROUND(AVG(DATE_DIFF(visit_end_date, visit_start_date, DAY)), 1) AS avg_los_days
FROM omop_visit_occurrence
GROUP BY visit_concept_id
ORDER BY visit_count DESC;
```

### Monthly Visit Volume Trend

```sql
SELECT
  FORMAT_DATE('%Y-%m', visit_start_date) AS month,
  COUNT(*) AS visit_count,
  COUNT(CASE WHEN visit_concept_id = 9201 THEN 1 END) AS inpatient,
  COUNT(CASE WHEN visit_concept_id = 9203 THEN 1 END) AS emergency
FROM omop_visit_occurrence
GROUP BY month
ORDER BY month;
```

---

## Readmission Analysis

### 30-Day All-Cause Readmission Rate

```sql
WITH inpatient_visits AS (
  SELECT
    person_id,
    visit_start_date,
    visit_end_date,
    LEAD(visit_start_date) OVER (
      PARTITION BY person_id ORDER BY visit_start_date
    ) AS next_admission_date
  FROM omop_visit_occurrence
  WHERE visit_concept_id = 9201  -- inpatient only
)
SELECT
  COUNT(*) AS total_discharges,
  COUNT(CASE
    WHEN DATE_DIFF(next_admission_date, visit_end_date, DAY) <= 30
    THEN 1
  END) AS readmissions_30d,
  ROUND(
    COUNT(CASE WHEN DATE_DIFF(next_admission_date, visit_end_date, DAY) <= 30 THEN 1 END)
    * 100.0 / COUNT(*), 1
  ) AS readmission_rate_pct
FROM inpatient_visits;
```

### Readmission Rate by Age Group

```sql
WITH inpatient AS (
  SELECT
    v.person_id,
    EXTRACT(YEAR FROM v.visit_start_date) - p.year_of_birth AS age_at_visit,
    v.visit_end_date,
    LEAD(v.visit_start_date) OVER (
      PARTITION BY v.person_id ORDER BY v.visit_start_date
    ) AS next_admission
  FROM omop_visit_occurrence v
  JOIN omop_person p ON v.person_id = p.person_id
  WHERE v.visit_concept_id = 9201
)
SELECT
  CASE
    WHEN age_at_visit < 50 THEN '<50'
    WHEN age_at_visit < 65 THEN '50-64'
    WHEN age_at_visit < 80 THEN '65-79'
    ELSE '80+'
  END AS age_group,
  COUNT(*) AS discharges,
  ROUND(COUNT(CASE WHEN DATE_DIFF(next_admission, visit_end_date, DAY) <= 30
                   THEN 1 END) * 100.0 / COUNT(*), 1) AS readmit_rate_pct
FROM inpatient
GROUP BY age_group
ORDER BY age_group;
```

---

## Condition Analysis

### Top 20 Conditions by Prevalence

```sql
SELECT
  condition_source_value AS snomed_code,
  COUNT(*) AS occurrences,
  COUNT(DISTINCT person_id) AS unique_patients,
  ROUND(COUNT(DISTINCT person_id) * 100.0 /
    (SELECT COUNT(DISTINCT person_id) FROM omop_person), 1) AS prevalence_pct
FROM omop_condition_occurrence
GROUP BY condition_source_value
ORDER BY unique_patients DESC
LIMIT 20;
```

### Comorbidity Pairs (Co-occurring Conditions)

```sql
WITH patient_conditions AS (
  SELECT DISTINCT person_id, condition_source_value
  FROM omop_condition_occurrence
)
SELECT
  a.condition_source_value AS condition_a,
  b.condition_source_value AS condition_b,
  COUNT(DISTINCT a.person_id) AS co_occurrence_count
FROM patient_conditions a
JOIN patient_conditions b
  ON a.person_id = b.person_id
  AND a.condition_source_value < b.condition_source_value
GROUP BY condition_a, condition_b
HAVING co_occurrence_count > 10
ORDER BY co_occurrence_count DESC
LIMIT 20;
```

---

## Medication Analysis

### Most Prescribed Medications

```sql
SELECT
  drug_source_value AS rxnorm_code,
  COUNT(*) AS prescription_count,
  COUNT(DISTINCT person_id) AS unique_patients
FROM omop_drug_exposure
GROUP BY drug_source_value
ORDER BY prescription_count DESC
LIMIT 20;
```

### Polypharmacy Distribution

```sql
SELECT
  medication_count,
  COUNT(*) AS patient_count
FROM (
  SELECT person_id, COUNT(DISTINCT drug_source_value) AS medication_count
  FROM omop_drug_exposure
  GROUP BY person_id
)
GROUP BY medication_count
ORDER BY medication_count;
```

---

## Lab Results (Measurements)

### Common Lab Values — Population Averages

```sql
SELECT
  measurement_source_value AS loinc_code,
  COUNT(*) AS measurement_count,
  ROUND(AVG(value_as_number), 2) AS avg_value,
  ROUND(STDDEV(value_as_number), 2) AS std_dev,
  unit_source_value AS unit
FROM omop_measurement
WHERE value_as_number IS NOT NULL
GROUP BY measurement_source_value, unit_source_value
ORDER BY measurement_count DESC
LIMIT 20;
```

### Abnormal Lab Values (2+ Standard Deviations)

```sql
WITH lab_stats AS (
  SELECT
    measurement_source_value,
    AVG(value_as_number) AS mean_val,
    STDDEV(value_as_number) AS std_val
  FROM omop_measurement
  WHERE value_as_number IS NOT NULL
  GROUP BY measurement_source_value
  HAVING COUNT(*) > 100
)
SELECT
  m.person_id,
  m.measurement_source_value AS lab,
  m.value_as_number,
  m.unit_source_value,
  m.measurement_date,
  ROUND((m.value_as_number - s.mean_val) / NULLIF(s.std_val, 0), 2) AS z_score
FROM omop_measurement m
JOIN lab_stats s ON m.measurement_source_value = s.measurement_source_value
WHERE ABS(m.value_as_number - s.mean_val) > 2 * s.std_val
ORDER BY ABS((m.value_as_number - s.mean_val) / NULLIF(s.std_val, 0)) DESC
LIMIT 50;
```

---

## Using ML Models

### Score Patients with the Readmission Predictor

```sql
SELECT
  person_id,
  predicted_readmitted_30d_probs[SAFE_OFFSET(0)].prob AS readmission_risk,
  CASE
    WHEN predicted_readmitted_30d_probs[SAFE_OFFSET(0)].prob > 0.7 THEN 'High'
    WHEN predicted_readmitted_30d_probs[SAFE_OFFSET(0)].prob > 0.3 THEN 'Medium'
    ELSE 'Low'
  END AS risk_tier
FROM ML.PREDICT(
  MODEL `your_dataset.readmission_predictor`,
  (SELECT * FROM your_dataset.readmission_features)
)
ORDER BY readmission_risk DESC;
```

### View Patient Segments

```sql
SELECT
  CENTROID_ID AS segment_id,
  COUNT(*) AS patient_count,
  ROUND(AVG(age), 0) AS avg_age,
  ROUND(AVG(total_conditions), 1) AS avg_conditions,
  ROUND(AVG(total_medications), 1) AS avg_medications,
  ROUND(AVG(total_visits), 1) AS avg_visits
FROM ML.PREDICT(
  MODEL `your_dataset.patient_segments`,
  (SELECT * FROM your_dataset.patient_features)
)
GROUP BY segment_id
ORDER BY patient_count DESC;
```

---

## References

- [OMOP CDM 5.4](https://ohdsi.github.io/CommonDataModel/cdm54.html) — table and field documentation
- [ATHENA](https://athena.ohdsi.org/) — OMOP concept browser
- [BigQuery SQL Reference](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax)
