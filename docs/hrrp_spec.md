# HRRP Penalty Savings Calculator

## Overview

A readmissions savings calculator that quantifies the financial impact of reducing 30-day readmissions under CMS's **Hospital Readmissions Reduction Program (HRRP)**. Builds on the existing `readmission_predictor` BQML model to translate clinical risk scores into dollar impact.

HRRP penalizes hospitals up to **3% of base DRG operating payments** for excess readmissions across 6 conditions. Even a 1% penalty on a mid-size hospital translates to **$500K–$2M/year** in lost revenue.

---

## HRRP Background

### Target Conditions (FY 2025)

| Condition | Measure ID |
|-----------|-----------|
| Acute Myocardial Infarction (AMI) | NQF #0505 |
| Heart Failure (HF) | NQF #0330 |
| Pneumonia | NQF #0506 |
| COPD | NQF #1891 |
| Coronary Artery Bypass Graft (CABG) | NQF #2515 |
| Total Hip/Knee Arthroplasty (THA/TKA) | NQF #1551 |

### Penalty Calculation

```
Excess Readmission Ratio (ERR) = Predicted Readmissions / Expected Readmissions

Payment Adjustment Factor = 1 - [ (sum of base DRG payments for excess readmissions)
                                   / (sum of base DRG payments for all discharges) ]

                           capped at max reduction of 3%
```

Since FY 2019, ERRs are calculated within **peer groups** based on dual-eligible (Medicare + Medicaid) patient proportion.

---

## Feature Spec

### Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `total_discharges` | int | Annual Medicare FFS discharges |
| `base_drg_revenue` | float | Total annual base DRG operating payments ($) |
| `condition_mix` | dict | Discharges per HRRP condition (AMI, HF, COPD, etc.) |
| `current_readmission_rates` | dict | Current 30-day readmission rate per condition (%) |
| `national_avg_rates` | dict | National average rates (pre-loaded, updated annually) |
| `dual_eligible_pct` | float | Percent of patients dually eligible (for peer grouping) |

### Outputs

| Output | Description |
|--------|-------------|
| **Current ERR** | Excess readmission ratio per condition |
| **Current penalty** | Estimated HRRP penalty amount ($) and % |
| **Target ERR** | ERR after intervention (using `readmission_predictor` scores) |
| **Projected savings** | Penalty reduction ($) if readmissions decrease |
| **Breakeven threshold** | Readmission rate needed to reach ERR ≤ 1.0 (no penalty) |
| **ROI per prevented readmission** | Dollar value of each avoided readmission |

### Calculation Engine

```python
def calculate_hrrp_penalty(condition_mix, readmission_rates, national_rates, base_drg_revenue):
    """
    For each HRRP condition:
      ERR = hospital_rate / expected_rate  (risk-adjusted)
      excess_payments = sum of base DRG payments for (predicted - expected) readmissions
    
    Payment adjustment = max(0, excess_payments / total_base_payments)
    Penalty = min(adjustment, 0.03) * base_drg_revenue
    """

def project_savings(current_penalty, target_reduction_pct, condition):
    """
    Model the penalty reduction from lowering readmission rates
    by a target percentage for a specific condition.
    """
```

---

## Integration with Avalon

### Using `readmission_predictor` for Targeting

```sql
-- Identify highest-risk patients for care management intervention
SELECT
  person_id,
  predicted_readmitted_30d_probs[SAFE_OFFSET(0)].prob AS readmission_risk,
  length_of_stay,
  total_conditions,
  prior_visits_1yr
FROM ML.PREDICT(MODEL `forge_synthetic_fhir.readmission_predictor`,
  (SELECT * FROM readmission_features))
WHERE predicted_readmitted_30d_probs[SAFE_OFFSET(0)].prob > 0.7
ORDER BY readmission_risk DESC;
```

### Scenario Modeling

The calculator should support "what-if" scenarios:

| Scenario | Question |
|----------|----------|
| **Baseline** | What is our current penalty exposure? |
| **Targeted intervention** | If we reduce HF readmissions by 15%, how much do we save? |
| **Risk stratification** | How many high-risk patients must we prevent from readmitting to eliminate the penalty? |
| **Condition priority** | Which condition gives the highest ROI per prevented readmission? |

---

## Implementation Plan

### Phase 1: Static Calculator (SQL + Python)

- BQML view that maps Avalon conditions to HRRP categories via SNOMED → ICD-10 crosswalk
- Python module `hrrp/savings_calculator.py` with penalty math
- CLI: `python3 -m hrrp.savings_calculator --discharges 5000 --drg-revenue 50000000`
- Outputs penalty estimate and savings projections as JSON

### Phase 2: Interactive Dashboard

- BigQuery-connected Looker Studio dashboard (or Streamlit app)
- Sliders for readmission rate targets per condition
- Real-time penalty recalculation
- Export PDF report for C-suite presentation

### Phase 3: Predictive Integration

- Connect `readmission_predictor` scores to the calculator
- Auto-identify which patients drive the most penalty exposure
- Generate care management worklists ranked by financial impact
- Alert when projected ERR crosses penalty thresholds

---

## National Average Readmission Rates (FY 2025 Reference)

| Condition | National Avg Rate | Typical Range |
|-----------|------------------|---------------|
| AMI | 15.5% | 12–19% |
| Heart Failure | 21.5% | 18–25% |
| Pneumonia | 16.0% | 13–19% |
| COPD | 19.5% | 17–23% |
| CABG | 12.5% | 10–16% |
| THA/TKA | 4.5% | 3–7% |

---

## Example: Mid-Size Hospital

```
Hospital:       500-bed community hospital
Discharges:     12,000/year Medicare FFS
Base DRG Rev:   $85,000,000/year
HF Discharges:  800/year
HF Rate:        23.5% (vs national 21.5%)

Current ERR:        1.093
Current Penalty:    ~0.8% = $680,000/year

If HF rate drops to 20.0%:
  New ERR:          0.930
  New Penalty:      $0
  Annual Savings:   $680,000

ROI per prevented readmission: $24,286
Readmissions to prevent:       28/year (3.5% reduction × 800)
```

---

## Dependencies

- `readmission_predictor` BQML model (deployed)
- SNOMED → ICD-10 crosswalk (for mapping Avalon conditions to HRRP categories)
- CMS IPPS final rule data (annual update for national rates and peer group thresholds)
