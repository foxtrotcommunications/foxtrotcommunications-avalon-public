#!/usr/bin/env python3
"""
Avalon OMOP Vocabulary Loader
==============================
Seeds the OHDSI Athena vocabulary into a dedicated BigQuery dataset
(foxtrot-communications-public.omop_vocab) for publishing via BigQuery Analytics Hub.

Two usage modes:

  1. Load from local Athena download (your one-time setup):
     python scripts/load_vocab.py \\
       --project foxtrot-communications-public \\
       --athena-dir /path/to/athena

  2. Subscribe via Analytics Hub (for end users — no Athena account needed):
     See README.md §Vocabulary Setup for the Analytics Hub subscription link.
     Once subscribed, set omop_vocab_project in your dbt_project.yml and run dbt.

Athena download instructions:
  1. Create a free account at https://athena.ohdsi.org/
  2. Click Download → select: SNOMED, LOINC, RxNorm, Gender, Race, Ethnicity
  3. Extract the ZIP, then run this script with --athena-dir pointing at the folder.
"""

import argparse
import os
import sys
import logging

logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")
log = logging.getLogger(__name__)

# Vocabularies used for FHIR → OMOP concept resolution
REQUIRED_VOCABS = {"SNOMED", "LOINC", "RxNorm", "UCUM", "Gender", "Race", "Ethnicity"}

# Relationships needed for "Maps to" standard concept resolution
REQUIRED_RELATIONSHIPS = {"Maps to", "Maps to value"}

# Analytics Hub listing (subscribers get omop_vocab in their own project)
ANALYTICS_HUB_LISTING_URL = (
    "https://console.cloud.google.com/bigquery/analytics-hub/discovery"
    "/projects/foxtrot-communications-public/locations/us"
    "/dataExchanges/avalon_omop_vocabulary_19ddad7deaa"
    "/listings/avalon_omop_vocabulary_19ddb11d777"
)


def parse_args():
    p = argparse.ArgumentParser(
        description="Load OHDSI Athena vocabulary into the dedicated omop_vocab BigQuery dataset"
    )
    p.add_argument(
        "--project",
        default="foxtrot-communications-public",
        help="GCP project to load vocab into (default: foxtrot-communications-public)",
    )
    p.add_argument(
        "--dataset",
        default="omop_vocab",
        help="BigQuery dataset name (default: omop_vocab)",
    )
    p.add_argument(
        "--location",
        default="US",
        help="BigQuery dataset location (default: US)",
    )
    p.add_argument(
        "--athena-dir",
        required=True,
        help="Path to extracted Athena vocabulary ZIP directory",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions without executing",
    )
    return p.parse_args()


def ensure_dataset(client, project, dataset, location, dry_run):
    from google.cloud import bigquery

    dataset_id = f"{project}.{dataset}"
    if dry_run:
        log.info(f"[dry-run] Would create dataset {dataset_id} if not exists")
        return
    ds = bigquery.Dataset(dataset_id)
    ds.location = location
    ds.description = (
        "OHDSI Standardized Vocabularies (SNOMED CT, LOINC, RxNorm) — "
        "filtered for FHIR → OMOP CDM 5.4 concept resolution. "
        "Published via BigQuery Analytics Hub as part of the Avalon OSS platform."
    )
    client.create_dataset(ds, exists_ok=True)
    log.info(f"✓ Dataset {dataset_id} ready")


def load_from_athena(client, project, dataset, athena_dir, dry_run):
    """Load and filter vocabulary tables from local Athena CSV files."""
    import pandas as pd
    from google.cloud import bigquery

    concept_path = os.path.join(athena_dir, "CONCEPT.csv")
    relationship_path = os.path.join(athena_dir, "CONCEPT_RELATIONSHIP.csv")

    for path in [concept_path, relationship_path]:
        if not os.path.exists(path):
            log.error(f"File not found: {path}")
            log.error(
                "Download from https://athena.ohdsi.org/ with: "
                "SNOMED, LOINC, RxNorm, Gender, Race, Ethnicity"
            )
            sys.exit(1)

    # ── concept ──────────────────────────────────────────────────────────────
    log.info("Reading CONCEPT.csv (this may take a moment)…")
    concept = pd.read_csv(
        concept_path,
        sep="\t",
        low_memory=False,
        dtype={"concept_id": "Int64"},
        parse_dates=["valid_start_date", "valid_end_date"],
    )
    before = len(concept)
    concept = concept[concept["vocabulary_id"].isin(REQUIRED_VOCABS)]
    log.info(
        f"Filtered concepts: {before:,} → {len(concept):,} "
        f"(vocabularies: {sorted(REQUIRED_VOCABS)})"
    )

    # ── concept_relationship ──────────────────────────────────────────────────
    log.info("Reading CONCEPT_RELATIONSHIP.csv…")
    rel = pd.read_csv(
        relationship_path,
        sep="\t",
        low_memory=False,
        dtype={"concept_id_1": "Int64", "concept_id_2": "Int64"},
        parse_dates=["valid_start_date", "valid_end_date"],
    )
    before = len(rel)
    valid_ids = set(concept["concept_id"].dropna().astype(int))
    rel = rel[
        rel["relationship_id"].isin(REQUIRED_RELATIONSHIPS)
        & rel["concept_id_1"].isin(valid_ids)
    ]
    log.info(f"Filtered relationships: {before:,} → {len(rel):,}")

    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE
    )

    for table_name, df in [("concept", concept), ("concept_relationship", rel)]:
        dest = f"{project}.{dataset}.{table_name}"
        if dry_run:
            log.info(f"[dry-run] Would load {len(df):,} rows → {dest}")
            continue
        log.info(f"Uploading {table_name} ({len(df):,} rows) to BigQuery…")
        load_job = client.load_table_from_dataframe(df, dest, job_config=job_config)
        load_job.result()
        log.info(f"✓ {table_name} → {dest}")


def create_concept_map_view(client, project, dataset, dry_run):
    """
    Create omop_vocab.concept_map — the pre-joined lookup used by OMOP dbt models.

    Maps: source_code + source_vocabulary → standard_concept_id
    """
    view_id = f"{project}.{dataset}.concept_map"
    sql = f"""
CREATE OR REPLACE VIEW `{view_id}` AS
SELECT
  c_src.concept_code   AS source_code,
  c_src.vocabulary_id  AS source_vocabulary,
  c_src.concept_id     AS source_concept_id,
  c_std.concept_id     AS standard_concept_id,
  c_std.concept_name   AS standard_concept_name,
  c_std.domain_id      AS domain_id,
  c_std.vocabulary_id  AS standard_vocabulary
FROM `{project}.{dataset}.concept`               c_src
JOIN `{project}.{dataset}.concept_relationship`  cr
  ON  cr.concept_id_1    = c_src.concept_id
  AND cr.relationship_id IN ('Maps to', 'Maps to value')
  AND cr.invalid_reason  IS NULL
JOIN `{project}.{dataset}.concept`               c_std
  ON  c_std.concept_id      = cr.concept_id_2
  AND c_std.standard_concept = 'S'
  AND c_std.invalid_reason   IS NULL
WHERE c_src.invalid_reason IS NULL
"""
    if dry_run:
        log.info(f"[dry-run] Would create view {view_id}")
        return
    from google.cloud import bigquery  # noqa: F401
    client.query(sql).result()
    log.info(f"✓ View {view_id} created")


def main():
    args = parse_args()

    try:
        from google.cloud import bigquery
        client = bigquery.Client(project=args.project)
    except ImportError:
        log.error("google-cloud-bigquery not installed.")
        log.error("Run: pip install google-cloud-bigquery pandas pyarrow")
        sys.exit(1)

    log.info(f"Project:   {args.project}")
    log.info(f"Dataset:   {args.dataset}")
    log.info(f"Location:  {args.location}")
    log.info(f"Athena dir: {args.athena_dir}")
    log.info("")

    ensure_dataset(client, args.project, args.dataset, args.location, args.dry_run)
    load_from_athena(client, args.project, args.dataset, args.athena_dir, args.dry_run)
    create_concept_map_view(client, args.project, args.dataset, args.dry_run)

    log.info("")
    log.info(f"✅  Vocabulary loaded to {args.project}.{args.dataset}")
    log.info("")
    log.info("Next steps:")
    log.info("  1. Run scripts/publish_vocab.py to publish to Analytics Hub")
    log.info("  2. Share the Analytics Hub listing URL with users")
    log.info(f"     {ANALYTICS_HUB_LISTING_URL}")


if __name__ == "__main__":
    main()
