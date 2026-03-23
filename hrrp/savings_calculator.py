#!/usr/bin/env python3
"""HRRP Penalty Savings Calculator — built from Avalon OMOP views.

Generates a 3D savings surface:
  - X: Readmission rate (%) — derived from OMOP visit_occurrence
  - Y: Base DRG operating payments ($) — simulated across hospital sizes
  - Z: CMS HRRP penalty / savings ($) — computed from OMOP-derived rates

All readmission rates and condition distributions come from the live
OMOP views. Hospital revenue is the only simulated axis.
"""

import argparse
import json
import sys
from typing import Dict, List

from google.cloud import bigquery
import numpy as np

# ═══════════════════════════════════════════════════════════════════
# HRRP Constants
# ═══════════════════════════════════════════════════════════════════

MAX_PENALTY_PCT = 0.03  # 3% cap

# SNOMED codes → HRRP condition category mapping
# These are the actual codes present in Avalon/Synthea data
SNOMED_TO_HRRP = {
    # AMI
    "22298006":  "AMI",   # Myocardial infarction
    "401303003": "AMI",   # Acute ST elevation MI
    "401314000": "AMI",   # Acute non-ST elevation MI
    "399211009": "AMI",   # History of MI
    # Heart Failure
    "88805009":  "HF",    # Chronic congestive heart failure
    "84114007":  "HF",    # Heart failure
    # Pneumonia
    "233604007": "Pneumonia",  # Pneumonia
    "10509002":  "Pneumonia",  # Acute bronchitis
    # COPD
    "185086009": "COPD",  # Chronic obstructive bronchitis
    "13645005":  "COPD",  # COPD
    # CABG (history indicates prior surgery)
    "399261000": "CABG",  # History of CABG
    # THA/TKA (joint replacement indicators)
    "239873007": "THA_TKA",  # Osteoarthritis of knee
    "239872002": "THA_TKA",  # Osteoarthritis of hip
}

# National average 30-day readmission rates (FY 2025)
NATIONAL_AVG_RATES = {
    "AMI":       0.155,
    "HF":        0.215,
    "Pneumonia":  0.160,
    "COPD":      0.195,
    "CABG":      0.125,
    "THA_TKA":   0.045,
}

# Average cost per readmission by condition
AVG_READMISSION_COST = {
    "AMI":       14_800,
    "HF":        13_500,
    "Pneumonia":  12_200,
    "COPD":      11_800,
    "CABG":      25_000,
    "THA_TKA":   16_500,
}


# ═══════════════════════════════════════════════════════════════════
# OMOP Data Extraction
# ═══════════════════════════════════════════════════════════════════


def build_snomed_case_sql() -> str:
    """Build a SQL CASE statement mapping SNOMED codes to HRRP categories."""
    lines = []
    for code, category in SNOMED_TO_HRRP.items():
        lines.append(f"    WHEN '{code}' THEN '{category}'")
    return "CASE condition_source_value\n" + "\n".join(lines) + "\n    ELSE NULL\n  END"


def extract_omop_rates(project: str, dataset: str) -> Dict:
    """Extract readmission rates from OMOP views using CMS index admission logic.

    CMS methodology:
      1. Identify qualifying inpatient visits with an active HRRP condition
      2. An INDEX ADMISSION is one where no prior admission for the same
         condition occurred in the preceding 90 days (avoids double-counting)
      3. A READMISSION is any inpatient/ER visit within 30 days of the
         index admission's discharge
      4. Each index admission produces at most one readmission flag

    Returns dict with OMOP-derived rates per HRRP condition.
    """
    client = bigquery.Client(project=project)
    fq = f"{project}.{dataset}"
    snomed_case = build_snomed_case_sql()

    sql = f"""
    WITH
    -- Step 1: Map conditions to HRRP categories with onset dates
    hrrp_conditions AS (
      SELECT
        person_id,
        {snomed_case} AS hrrp_category,
        TIMESTAMP(condition_start_date) AS condition_onset
      FROM `{fq}.omop_condition_occurrence`
      WHERE condition_source_value IN ({','.join(f"'{c}'" for c in SNOMED_TO_HRRP.keys())})
    ),

    -- Step 2: Join inpatient visits to temporally-active HRRP conditions
    --   A condition is "active" if its onset is on or before the visit start
    condition_visits AS (
      SELECT
        v.person_id,
        v.visit_occurrence_id,
        v.visit_concept_id,
        v.visit_start_datetime,
        v.visit_end_datetime,
        TIMESTAMP_DIFF(v.visit_end_datetime, v.visit_start_datetime, HOUR) AS los_hours,
        hc.hrrp_category,
        -- Look back: when was the previous visit for this patient + condition?
        LAG(v.visit_end_datetime) OVER (
          PARTITION BY v.person_id, hc.hrrp_category
          ORDER BY v.visit_start_datetime
        ) AS prev_discharge_same_condition
      FROM `{fq}.omop_visit_occurrence` v
      INNER JOIN hrrp_conditions hc
        ON v.person_id = hc.person_id
        AND hc.condition_onset <= v.visit_start_datetime
      WHERE v.visit_end_datetime IS NOT NULL
        AND v.visit_concept_id IN (9201, 9203)  -- Inpatient + ER only
      QUALIFY ROW_NUMBER() OVER (
        PARTITION BY v.visit_occurrence_id, hc.hrrp_category
        ORDER BY hc.condition_onset DESC
      ) = 1  -- dedupe: one row per visit per HRRP category
    ),

    -- Step 3: Index admissions = visits with no prior same-condition
    --   discharge in the preceding 90 days
    index_admissions AS (
      SELECT *
      FROM condition_visits
      WHERE prev_discharge_same_condition IS NULL
         OR TIMESTAMP_DIFF(visit_start_datetime, prev_discharge_same_condition, DAY) > 90
    ),

    -- Step 4: Flag 30-day readmissions against index admissions
    --   A readmission is ANY subsequent inpatient/ER visit within 30 days
    index_with_readmission AS (
      SELECT
        ia.*,
        MAX(CASE WHEN rv.visit_occurrence_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
      FROM index_admissions ia
      LEFT JOIN `{fq}.omop_visit_occurrence` rv
        ON ia.person_id = rv.person_id
        AND rv.visit_occurrence_id != ia.visit_occurrence_id
        AND rv.visit_concept_id IN (9201, 9203)
        AND rv.visit_start_datetime BETWEEN ia.visit_end_datetime
            AND TIMESTAMP_ADD(ia.visit_end_datetime, INTERVAL 30 DAY)
      GROUP BY ia.person_id, ia.visit_occurrence_id, ia.visit_concept_id,
               ia.visit_start_datetime, ia.visit_end_datetime, ia.los_hours,
               ia.hrrp_category, ia.prev_discharge_same_condition
    ),

    -- Also compute overall stats from ALL inpatient/ER visits (not just HRRP)
    all_inpatient AS (
      SELECT
        v1.person_id,
        v1.visit_occurrence_id,
        v1.visit_start_datetime,
        v1.visit_end_datetime,
        TIMESTAMP_DIFF(v1.visit_end_datetime, v1.visit_start_datetime, HOUR) AS los_hours,
        -- 90-day lookback for index admission (all-cause)
        LAG(v1.visit_end_datetime) OVER (
          PARTITION BY v1.person_id ORDER BY v1.visit_start_datetime
        ) AS prev_discharge
      FROM `{fq}.omop_visit_occurrence` v1
      WHERE v1.visit_end_datetime IS NOT NULL
        AND v1.visit_concept_id IN (9201, 9203)
    ),
    all_index AS (
      SELECT *
      FROM all_inpatient
      WHERE prev_discharge IS NULL
         OR TIMESTAMP_DIFF(visit_start_datetime, prev_discharge, DAY) > 90
    ),
    all_index_readmit AS (
      SELECT
        ai.*,
        MAX(CASE WHEN rv.visit_occurrence_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
      FROM all_index ai
      LEFT JOIN `{fq}.omop_visit_occurrence` rv
        ON ai.person_id = rv.person_id
        AND rv.visit_occurrence_id != ai.visit_occurrence_id
        AND rv.visit_concept_id IN (9201, 9203)
        AND rv.visit_start_datetime BETWEEN ai.visit_end_datetime
            AND TIMESTAMP_ADD(ai.visit_end_datetime, INTERVAL 30 DAY)
      GROUP BY ai.person_id, ai.visit_occurrence_id, ai.visit_start_datetime,
               ai.visit_end_datetime, ai.los_hours, ai.prev_discharge
    )

    -- Aggregate
    SELECT
      -- Overall (all-cause index admissions)
      (SELECT COUNT(*) FROM all_index_readmit) AS total_index_admissions,
      (SELECT COUNT(DISTINCT person_id) FROM all_index_readmit) AS total_patients,
      (SELECT SUM(readmitted_30d) FROM all_index_readmit) AS total_readmitted,
      (SELECT ROUND(AVG(readmitted_30d), 4) FROM all_index_readmit) AS overall_readmission_rate,
      (SELECT ROUND(AVG(los_hours), 1) FROM all_index_readmit) AS avg_los_hours,

      -- Per-condition (HRRP index admissions)
      COUNTIF(hrrp_category = 'AMI') AS ami_index,
      ROUND(SAFE_DIVIDE(
        COUNTIF(hrrp_category = 'AMI' AND readmitted_30d = 1),
        NULLIF(COUNTIF(hrrp_category = 'AMI'), 0)
      ), 4) AS ami_rate,

      COUNTIF(hrrp_category = 'HF') AS hf_index,
      ROUND(SAFE_DIVIDE(
        COUNTIF(hrrp_category = 'HF' AND readmitted_30d = 1),
        NULLIF(COUNTIF(hrrp_category = 'HF'), 0)
      ), 4) AS hf_rate,

      COUNTIF(hrrp_category = 'Pneumonia') AS pneumonia_index,
      ROUND(SAFE_DIVIDE(
        COUNTIF(hrrp_category = 'Pneumonia' AND readmitted_30d = 1),
        NULLIF(COUNTIF(hrrp_category = 'Pneumonia'), 0)
      ), 4) AS pneumonia_rate,

      COUNTIF(hrrp_category = 'COPD') AS copd_index,
      ROUND(SAFE_DIVIDE(
        COUNTIF(hrrp_category = 'COPD' AND readmitted_30d = 1),
        NULLIF(COUNTIF(hrrp_category = 'COPD'), 0)
      ), 4) AS copd_rate,

      COUNTIF(hrrp_category = 'CABG') AS cabg_index,
      ROUND(SAFE_DIVIDE(
        COUNTIF(hrrp_category = 'CABG' AND readmitted_30d = 1),
        NULLIF(COUNTIF(hrrp_category = 'CABG'), 0)
      ), 4) AS cabg_rate,

      COUNTIF(hrrp_category = 'THA_TKA') AS tha_tka_index,
      ROUND(SAFE_DIVIDE(
        COUNTIF(hrrp_category = 'THA_TKA' AND readmitted_30d = 1),
        NULLIF(COUNTIF(hrrp_category = 'THA_TKA'), 0)
      ), 4) AS tha_tka_rate

    FROM index_with_readmission
    """

    print("  Querying OMOP views (CMS index admission logic)...")
    result = list(client.query(sql).result())[0]

    omop_data = {
        "total_visits": result.total_index_admissions,
        "total_patients": result.total_patients,
        "total_readmitted": result.total_readmitted,
        "overall_rate": float(result.overall_readmission_rate or 0),
        "avg_los_hours": float(result.avg_los_hours or 0),
        "condition_rates": {},
        "condition_visits": {},
    }

    for cond, col_prefix in [
        ("AMI", "ami"), ("HF", "hf"), ("Pneumonia", "pneumonia"),
        ("COPD", "copd"), ("CABG", "cabg"), ("THA_TKA", "tha_tka"),
    ]:
        visits = getattr(result, f"{col_prefix}_index")
        rate = getattr(result, f"{col_prefix}_rate")
        omop_data["condition_visits"][cond] = visits
        omop_data["condition_rates"][cond] = float(rate) if rate else None

    return omop_data


# ═══════════════════════════════════════════════════════════════════
# Penalty Calculation (OMOP-derived)
# ═══════════════════════════════════════════════════════════════════


def compute_penalty_from_omop(
    omop_data: Dict,
    base_drg_revenue: float,
    rate_multiplier: float = 1.0,
) -> Dict:
    """Compute HRRP penalty using OMOP-derived rates.

    Args:
        omop_data: Output from extract_omop_rates().
        base_drg_revenue: Simulated annual base DRG revenue.
        rate_multiplier: Scale factor for readmission rates (1.0 = actual OMOP rates).
    """
    total_excess_cost = 0.0
    condition_details = {}

    # Scale discharges to hospital size (proportional to revenue)
    scale_factor = base_drg_revenue / 85_000_000  # normalized to ~$85M baseline
    total_discharges = int(omop_data["total_visits"] * scale_factor)

    for cond in NATIONAL_AVG_RATES:
        nat_rate = NATIONAL_AVG_RATES[cond]
        readmit_cost = AVG_READMISSION_COST[cond]

        # Use OMOP-derived rate, scaled by multiplier
        omop_rate = omop_data["condition_rates"].get(cond)
        if omop_rate is None or omop_rate == 0:
            omop_rate = nat_rate  # fallback to national if no data
        hospital_rate = min(omop_rate * rate_multiplier, 0.50)

        # Scale condition visits to hospital size
        omop_cond_visits = omop_data["condition_visits"].get(cond, 0)
        if omop_data["total_visits"] > 0:
            cond_fraction = omop_cond_visits / omop_data["total_visits"]
        else:
            cond_fraction = 0.05
        condition_discharges = max(1, int(total_discharges * cond_fraction))

        err = hospital_rate / nat_rate if nat_rate > 0 else 1.0
        predicted = condition_discharges * hospital_rate
        expected = condition_discharges * nat_rate
        excess = max(0, predicted - expected)
        excess_cost = excess * readmit_cost
        total_excess_cost += excess_cost

        condition_details[cond] = {
            "omop_rate": round(omop_rate, 4),
            "adjusted_rate": round(hospital_rate, 4),
            "national_rate": nat_rate,
            "err": round(err, 4),
            "discharges": condition_discharges,
            "excess_readmissions": round(excess, 1),
        }

    raw_adjustment = total_excess_cost / base_drg_revenue if base_drg_revenue > 0 else 0
    penalty_pct = min(raw_adjustment, MAX_PENALTY_PCT)
    penalty_amount = penalty_pct * base_drg_revenue

    actual_rate = omop_data["overall_rate"] * rate_multiplier

    return {
        "readmission_rate_pct": round(actual_rate * 100, 2),
        "base_drg_revenue": base_drg_revenue,
        "total_discharges": total_discharges,
        "penalty_pct": round(penalty_pct * 100, 4),
        "penalty_amount": round(penalty_amount, 2),
        "total_excess_readmissions": round(sum(
            c["excess_readmissions"] for c in condition_details.values()
        ), 1),
        "weighted_err": round(np.mean([
            c["err"] for c in condition_details.values()
        ]), 4),
        "conditions": condition_details,
    }


# ═══════════════════════════════════════════════════════════════════
# 3D Surface Generator (OMOP-grounded)
# ═══════════════════════════════════════════════════════════════════


def generate_surface(
    omop_data: Dict,
    rate_multipliers: np.ndarray = None,
    revenue_range: np.ndarray = None,
) -> List[Dict]:
    """Generate 3D surface from OMOP data.

    X-axis: readmission rate (OMOP rate × multiplier)
    Y-axis: base DRG revenue (simulated hospital sizes)
    Z-axis: CMS penalty amount
    """
    if rate_multipliers is None:
        # From 0.3x to 2.5x the OMOP-observed rate
        rate_multipliers = np.linspace(0.3, 2.5, 45)
    if revenue_range is None:
        revenue_range = np.linspace(10_000_000, 500_000_000, 50)

    rows = []
    for mult in rate_multipliers:
        for revenue in revenue_range:
            result = compute_penalty_from_omop(omop_data, float(revenue), float(mult))

            rows.append({
                "readmission_rate_pct": result["readmission_rate_pct"],
                "rate_multiplier": round(float(mult), 3),
                "base_drg_revenue": result["base_drg_revenue"],
                "total_discharges": result["total_discharges"],
                "penalty_pct": result["penalty_pct"],
                "penalty_amount": result["penalty_amount"],
                "savings_if_at_national_avg": result["penalty_amount"],
                "savings_per_prevented_readmission": round(
                    result["penalty_amount"] / max(1, result["total_excess_readmissions"]), 2
                ),
                "total_excess_readmissions": result["total_excess_readmissions"],
                "weighted_err": result["weighted_err"],
                "err_ami": result["conditions"]["AMI"]["err"],
                "err_hf": result["conditions"]["HF"]["err"],
                "err_pneumonia": result["conditions"]["Pneumonia"]["err"],
                "err_copd": result["conditions"]["COPD"]["err"],
                "err_cabg": result["conditions"]["CABG"]["err"],
                "err_tha_tka": result["conditions"]["THA_TKA"]["err"],
            })

    return rows


def load_to_bigquery(rows: List[Dict], project: str, dataset: str = "forge_synthetic_fhir"):
    """Load the surface dataset to BigQuery."""
    client = bigquery.Client(project=project)
    table_id = f"{project}.{dataset}.hrrp_savings_surface"

    schema = [
        bigquery.SchemaField("readmission_rate_pct", "FLOAT64",
                             description="OMOP-derived 30-day readmission rate (%)"),
        bigquery.SchemaField("rate_multiplier", "FLOAT64",
                             description="Multiplier applied to OMOP base rate (1.0 = actual)"),
        bigquery.SchemaField("base_drg_revenue", "FLOAT64",
                             description="Simulated annual base DRG operating payments ($)"),
        bigquery.SchemaField("total_discharges", "INT64",
                             description="Scaled annual discharges based on OMOP distribution"),
        bigquery.SchemaField("penalty_pct", "FLOAT64",
                             description="HRRP payment reduction (%, capped at 3%)"),
        bigquery.SchemaField("penalty_amount", "FLOAT64",
                             description="Annual HRRP penalty ($)"),
        bigquery.SchemaField("savings_if_at_national_avg", "FLOAT64",
                             description="Savings if rates match national averages ($)"),
        bigquery.SchemaField("savings_per_prevented_readmission", "FLOAT64",
                             description="Dollar value per prevented readmission ($)"),
        bigquery.SchemaField("total_excess_readmissions", "FLOAT64",
                             description="Total excess readmissions above expected"),
        bigquery.SchemaField("weighted_err", "FLOAT64",
                             description="Average ERR across 6 HRRP conditions"),
        bigquery.SchemaField("err_ami", "FLOAT64", description="ERR: Acute MI"),
        bigquery.SchemaField("err_hf", "FLOAT64", description="ERR: Heart Failure"),
        bigquery.SchemaField("err_pneumonia", "FLOAT64", description="ERR: Pneumonia"),
        bigquery.SchemaField("err_copd", "FLOAT64", description="ERR: COPD"),
        bigquery.SchemaField("err_cabg", "FLOAT64", description="ERR: CABG Surgery"),
        bigquery.SchemaField("err_tha_tka", "FLOAT64", description="ERR: Hip/Knee Arthroplasty"),
    ]

    job_config = bigquery.LoadJobConfig(
        schema=schema,
        write_disposition="WRITE_TRUNCATE",
    )

    job = client.load_table_from_json(rows, table_id, job_config=job_config)
    job.result()

    table = client.get_table(table_id)
    table.description = (
        "HRRP penalty savings surface derived from Avalon OMOP views. "
        "Readmission rates are computed from omop_visit_occurrence (inpatient/ER), "
        "condition distributions from omop_condition_occurrence mapped to HRRP categories. "
        "Revenue axis is simulated. Each row is a synthetic hospital scenario."
    )
    client.update_table(table, ["description"])

    print(f"  Loaded {len(rows):,} rows to {table_id}")
    return table_id


# ═══════════════════════════════════════════════════════════════════
# GCS Export (for web frontend)
# ═══════════════════════════════════════════════════════════════════


def export_to_gcs(
    rows: List[Dict],
    omop_data: Dict,
    project: str,
    bucket_name: str = None,
    gcs_path: str = "hrrp/hrrp_savings_surface.json",
):
    """Export surface data to GCS as Plotly-ready JSON for the web frontend.

    Formats data as matrices for Plotly's 3D surface chart:
      - x: readmission rates
      - y: revenue values
      - z: penalty amounts (matrix)
    """
    from google.cloud import storage
    import json

    if bucket_name is None:
        bucket_name = f"{project}-avalon-synthea"

    # Build Plotly-ready matrices
    rates = sorted(set(r["readmission_rate_pct"] for r in rows))
    revenues = sorted(set(r["base_drg_revenue"] for r in rows))

    lookup = {(r["readmission_rate_pct"], r["base_drg_revenue"]): r for r in rows}

    z_penalty = []
    z_pct = []
    z_excess = []
    z_savings_per = []
    for rate in rates:
        row_penalty, row_pct, row_excess, row_spr = [], [], [], []
        for rev in revenues:
            r = lookup.get((rate, rev))
            row_penalty.append(round(r["penalty_amount"], 0) if r else 0)
            row_pct.append(round(r["penalty_pct"], 3) if r else 0)
            row_excess.append(round(r["total_excess_readmissions"], 0) if r else 0)
            row_spr.append(round(r["savings_per_prevented_readmission"], 0) if r else 0)
        z_penalty.append(row_penalty)
        z_pct.append(row_pct)
        z_excess.append(row_excess)
        z_savings_per.append(row_spr)

    surface_data = {
        "rates": [round(r, 2) for r in rates],
        "revenues": [round(r, 0) for r in revenues],
        "penaltyAmount": z_penalty,
        "penaltyPct": z_pct,
        "excessReadmissions": z_excess,
        "savingsPerPrevented": z_savings_per,
        "baseline": {
            "overallRate": round(omop_data["overall_rate"] * 100, 1),
            "totalVisits": omop_data["total_visits"],
            "totalPatients": omop_data["total_patients"],
            "avgLosHours": round(omop_data["avg_los_hours"], 0),
            "conditions": {
                cond: {
                    "visits": omop_data["condition_visits"].get(cond, 0),
                    "rate": round(omop_data["condition_rates"].get(cond, 0) * 100, 1)
                        if omop_data["condition_rates"].get(cond) else None,
                    "nationalRate": round(NATIONAL_AVG_RATES[cond] * 100, 1),
                }
                for cond in NATIONAL_AVG_RATES
            },
        },
    }

    # Upload to GCS
    client = storage.Client(project=project)
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(gcs_path)
    blob.upload_from_string(
        json.dumps(surface_data),
        content_type="application/json",
    )
    print(f"  Exported to gs://{bucket_name}/{gcs_path} ({len(json.dumps(surface_data)):,} bytes)")
    return f"gs://{bucket_name}/{gcs_path}"


# ═══════════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════════


def main():
    parser = argparse.ArgumentParser(
        description="HRRP Savings Calculator — derived from Avalon OMOP views"
    )
    parser.add_argument("--project", default="foxtrot-communications-public")
    parser.add_argument("--dataset", default="forge_synthetic_fhir")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--rate-steps", type=int, default=45)
    parser.add_argument("--revenue-steps", type=int, default=50)

    args = parser.parse_args()

    print("=" * 60)
    print("HRRP Penalty Savings — OMOP-Derived 3D Surface")
    print("=" * 60)

    # Step 1: Extract rates from OMOP
    print("\nStep 1: Extracting from OMOP views...")
    omop_data = extract_omop_rates(args.project, args.dataset)

    print(f"\n  OMOP baseline:")
    print(f"    Inpatient/ER visits:  {omop_data['total_visits']:,}")
    print(f"    Unique patients:      {omop_data['total_patients']:,}")
    print(f"    Overall readmit rate: {omop_data['overall_rate']*100:.1f}%")
    print(f"    Avg LOS:              {omop_data['avg_los_hours']:.0f} hours")
    print(f"\n  HRRP condition rates (from OMOP):")
    for cond in NATIONAL_AVG_RATES:
        visits = omop_data["condition_visits"].get(cond, 0)
        rate = omop_data["condition_rates"].get(cond)
        nat = NATIONAL_AVG_RATES[cond]
        rate_str = f"{rate*100:.1f}%" if rate else "N/A"
        err_str = f"{rate/nat:.2f}" if rate else "—"
        print(f"    {cond:12s}  visits={visits:>4d}  rate={rate_str:>6s}  "
              f"national={nat*100:.1f}%  ERR={err_str}")

    # Step 2: Generate surface
    print(f"\nStep 2: Generating {args.rate_steps} × {args.revenue_steps} = "
          f"{args.rate_steps * args.revenue_steps:,} scenarios...")
    rows = generate_surface(
        omop_data,
        rate_multipliers=np.linspace(0.3, 2.5, args.rate_steps),
        revenue_range=np.linspace(10_000_000, 500_000_000, args.revenue_steps),
    )
    print(f"  Generated {len(rows):,} rows")

    # Sample at 1.0x multiplier (actual OMOP rates)
    actual = [r for r in rows if abs(r["rate_multiplier"] - 1.0) < 0.05
              and abs(r["base_drg_revenue"] - 85_000_000) < 10_000_000]
    if actual:
        s = actual[0]
        print(f"\n  At OMOP actual rates + $85M revenue:")
        print(f"    Rate:     {s['readmission_rate_pct']:.1f}%")
        print(f"    Penalty:  ${s['penalty_amount']:,.0f} ({s['penalty_pct']:.2f}%)")
        print(f"    Excess:   {s['total_excess_readmissions']:.0f} readmissions")

    # Step 3: Load
    if args.dry_run:
        print(f"\n  [DRY RUN] Would load {len(rows):,} rows to BigQuery + GCS")
    else:
        print(f"\nStep 3: Loading to BigQuery...")
        table_id = load_to_bigquery(rows, args.project, args.dataset)

        print(f"\nStep 4: Exporting to GCS for web frontend...")
        gcs_uri = export_to_gcs(rows, omop_data, args.project)

        print(f"\n{'=' * 60}")
        print(f"Done — query with:")
        print(f"  SELECT * FROM `{table_id}` ORDER BY penalty_amount DESC LIMIT 10")
        print(f"{'=' * 60}")


if __name__ == "__main__":
    main()
